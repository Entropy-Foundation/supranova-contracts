module token_bridge_service::token_bridge_service {
    use std::signer;
    use std::vector;
    use std::chain_id;
    use aptos_std::from_bcs;
    use aptos_std::smart_table::{Self, SmartTable};
    use supra_framework::account::{Self, SignerCapability};
    use supra_framework::object::{Self, Object};
    use supra_framework::event::emit;
    use supra_framework::primary_fungible_store;
    use supra_framework::fungible_asset::{Self, FungibleAsset, Metadata, balance};
    use supra_framework::block;
    use supra_framework::timestamp;
    use hypernova_core::message_types::{get_data, ExtractedLog, get_topics};
    use hypernova_core::helpers::bytes_to_u64;
    use hypernova_core::proof_verifier::{
        process_data_optimistic_or_safe,
        process_data_finality
    };
    use wrapped_token_deployer::wrapped_token_deployer::{
        is_token_active,
        get_wrapped_token_address,
        mint_wrapped_token,
        claim_minter_capability_for_token,
        generate_token_identifier_hash
    };

    /// === Errors ===

    /// The token bridge is currently paused. The token bridge operation is paused and cannot be executed.
    const ETOKEN_BRIDGE_PAUSED: u64 = 1000;

    /// Unauthorized access attempt by a non-owner of the token bridge. The access was denied due to the non-owner attempting to interact with the bridge.
    const EUNAUTHORIZED_TOKEN_BRIDGE_ADMIN: u64 = 1001;

    /// The source bridge address does not match the expected value. The provided source bridge address is incorrect or does not match the expected one.
    const ESOURCE_BRIDGE_ADDRESS_MISMATCH: u64 = 1002;

    /// The source bridge chain ID does not match the expected value. The provided chain ID for the source bridge is incorrect or mismatched.
    const ESOURCE_BRIDGE_CHAIN_ID_MISMATCH: u64 = 1003;

    /// The source token bridge address is invalid. The source token bridge address provided is invalid or does not match the expected address.
    const EINVALID_SOURCE_TOKEN_BRIDGE_ADDRESS: u64 = 1004;

    /// The size of the message data is invalid. The size of the provided message data does not match the expected or valid range.
    const EINVALID_MESSAGE_DATA_SIZE: u64 = 1005;

    /// The specified event has already been executed. The event has already been processed, and cannot be executed again.
    const EEVENT_ALREADY_EXECUTED: u64 = 1006;

    /// The token is not active. The token is inactive and cannot be used or operated on.
    const ETOKEN_NOT_ACTIVE: u64 = 1007;

    /// The token is not registered. The token has not been registered within the system and cannot be used.
    const ETOKEN_NOT_REGISTERED: u64 = 1008;

    /// The number of event topics is invalid. The number of topics provided for the event does not meet the expected or valid number.
    const EINVALID_EVENT_TOPICS_LENGTH: u64 = 1009;

    /// Invalid safety level. The provided safety level must be greater than or equal to the minimum required safety level
    const EINVALID_SAFETY_LEVEL: u64 = 1010;

    /// Maximum verification strategy types exceeded. The number of verification strategies exceeds the maximum allowed.
    const EINVALID_VERIFICATION_STRATEGY_TYPE_RANGE: u64 = 1011;

    /// This error is raised when the relayer reward exceeds or equals the total bridge service fee, resulting in an invalid or negative net fee.
    const EINVALID_FEES: u64 = 1012;

    /// === Constants ===

    /// Seed value used for token bridge operations.
    const TOKEN_BRIDGE_SEED: vector<u8> = b"ETH_SUPRA_TOKEN_BRIDGE_SEED";

    /// The length of an Ethereum address when padded to 32 bytes.
    const ETHEREUM_PADDED_ADDRESS_LEN: u64 = 32;

    /// Represents the finality verification method.
    const FINALITY_VERIFICATION_METHOD: u8 = 1;

    /// Represents the optimistic verification method.
    const OPTIMISTIC_VERIFICATION_METHOD: u8 = 3;

    /// The size of message data in bytes.
    /// @notice: 256 bytes if we use abi.encodePacked() on the source.
    const MESSAGE_DATA_SIZE: u64 = 320;

    /// The number of the event topics.
    const NUM_EVENT_TOPICS: u64 = 3;

    /// The minimum safety level for the verifier.
    const MIN_SAFETY_LEVEL: u8 = 2;

    /// Minimum supported verification strategy type.
    const MIN_VERIFICATION_STRATEGY_TYPE: u8 = 1;

    /// Maximum supported verification strategy type.
    const MAX_VERIFICATION_STRATEGY_TYPE: u8 = 3;

    /// safe level will be zero for finality and Optimistic
    const SAFE_LEVEL_DEFAULT: u8 = 0;

    /// Byte range constants for extracting fields from `message_data`
    /// Each field is 32 bytes (standard word size, e.g., Ethereum-style ABI encoding)

    /// Header field offsets in the message_data (each field is 32 bytes)
    const SENDER_ADDR_START: u64 = 64;
    const SENDER_ADDR_END: u64 = 96;

    const SOURCE_TOKEN_ADDR_START: u64 = 96;
    const SOURCE_TOKEN_ADDR_END: u64 = 128;

    const SOURCE_CHAIN_ID_START: u64 = 128;
    const SOURCE_CHAIN_ID_END: u64 = 160;

    const TRANSFER_PAYLOAD_START: u64 = 160;
    /// start of transfer payload (bytes 160 ,192)
    const TRANSFER_PAYLOAD_END: u64 = 192;

    const FINAL_AMOUNT_START: u64 = 192;
    /// start of final token amount (bytes 192, 224)
    const FINAL_AMOUNT_END: u64 = 224;

    const FEE_CUT_START: u64 = 224;
    /// start of fee cut to service (bytes 224,256)
    const FEE_CUT_END: u64 = 256;

    const RELAYER_REWARD_START: u64 = 256;
    /// start of relayer reward amount (bytes 256,288)
    const RELAYER_REWARD_END: u64 = 288;

    const RECIPIENT_ADDR_START: u64 = 288;
    /// start of recipient address (bytes 288,320)
    const RECIPIENT_ADDR_END: u64 = 320;


    // === Structs ===

    #[resource_group_member(group = supra_framework::object::ObjectGroup)]
    /// Main state container for the token bridge service.
    ///
    /// # Overview
    /// Manages the operational state and configuration of the cross-chain token bridge,
    /// including administrative controls, event tracking, and token mappings.
    ///
    /// # Fields
    /// - safety_level: The safety level parameter that determines the security threshold for verification
    /// - verification_strategy_type: The type of verification strategy to be used (e.g., optimistic, safe, finality)
    /// - is_paused: Indicates whether the token bridge is currently paused
    /// - admin_addr: The address of the bridge admin who has control over the token bridge operations
    /// - bridge_signer_capability: The capability of the bridge signer, used for signing operations
    /// - source_bridge_info: Information about the source token bridge, including chain ID and address
    /// - processed_event_hashes: A smart table that tracks hashes of processed events to prevent replay attacks
    struct TokenBridgeState has key {
        safety_level: u8,
        verification_strategy_type: u8,
        is_paused: bool,
        admin_addr: address,
        bridge_signer_capability: SignerCapability,
        source_bridge_info: SourceTokenBridgeInfo,
        processed_event_hashes: SmartTable<vector<u8>, bool>
    }


    /// Configuration of the token bridge on the source chain.
    ///
    /// # Overview
    /// Contains the necessary information to interact with the
    /// token bridge contract on the source blockchain.
    ///
    /// # Fields
    /// - chain_id: Identifier of the source blockchain
    /// - bridge_addr: Address of token bridge contract on source chain
    struct SourceTokenBridgeInfo has store {
        chain_id: u64,
        bridge_addr: vector<u8>
    }

    /// View struct representing verification configuration.
    struct VerificationInfo has copy, drop, store {
        /// Verification strategy type (e.g., optimistic, safe, etc.)
        verification_strategy_type: u8,

        /// Safety level associated with the strategy.
        safety_level: u8,
    }

    /// Contains the source token bridges address and its corresponding chain ID.
    struct SourceBridgeInfo has copy, drop, store {
        /// The address of the source token bridge, encoded as bytes.
        bridge_address: vector<u8>,

        /// The chain ID where the source token bridge is deployed.
        chain_id: u64,
    }


    // === Events ===

    #[event]
    /// Event emitted when the token bridges pause status changes.
    /// This event tracks when the bridge is paused or unpaused for maintenance or emergencies.
    struct TokenBridgePauseEvent has drop, store {
        /// Boolean indicating whether the bridge is being paused (true) or unpaused (false)
        is_paused: bool
    }


    #[event]
    /// Event emitted when a new source token bridge is registered.
    /// This event tracks the addition of new source chains to the bridge network.
    struct SourceTokenBridgeRegisterEvent has drop, store {
        /// Chain ID of the newly registered source blockchain
        source_chain_id: u64,
        /// Address of the token bridge contract on the source chain
        source_token_bridge_addr: vector<u8>
    }

    #[event]
    /// Event emitted when a source token bridge is unregistered from the network.
    /// This event provides tracking information about removed source chain connections.
    struct SourceTokenBridgeUnRegisterEvent has drop, store {
        /// The unique identifier of the source blockchain being unregistered
        source_chain_id: u64,
        /// The contract address of the token bridge on the source chain
        source_token_bridge_addr: vector<u8>
    }

    #[event]
    /// Event emitted when a cross-chain message is executed.
    /// This event tracks the successful processing of messages between chains,
    /// including all necessary identifiers for verification and tracking.
    struct ExecutionEvent has store, drop {
        /// Index of the log entry in the source chains event log
        log_index: u64,
        /// Unique identifier for the message, used for deduplication
        message_id: vector<u8>,
        /// Hash of the log entry containing the message, used for verification
        extracted_log_hash: vector<u8>
    }

    #[event]
    /// Event emitted when message data is extracted from a cross-chain transaction.
    /// This event contains all necessary metadata required to track, validate,
    /// and process token transfers across blockchains, including amounts, fees,
    /// timestamps, and addresses involved in the message flow.
    struct ExtractedMessageDataEvent has store, drop {
        /// verification method used for the transaction
        verification_strategy_type: u8,
        /// safety level used for the transaction
        safety_level: u8,
        /// Amount of tokens being transferred
        amount: u64,
        /// Fee charged by the bridge service
        bridge_service_fee: u64,
        /// Reward for the relayer who processed the transaction
        relayer_reward: u64,
        /// Chain ID where tokens are being delivered
        dest_chain_id: u8,
        /// Block height when processed
        dest_block_height: u64,
        /// When the transaction was processed
        dest_timestamp: u64,
        /// Address of the wrapped token on destination
        dest_token_addr: address,
        /// Chain ID of the source blockchain
        source_chain_id: u64,
        /// Unique identifier for the cross-chain transaction
        message_id: vector<u8>,
        /// Address of the token bridge on the source chain
        source_token_bridge_addr: vector<u8>,
        /// Address of the token sender on the source chain
        sender_addr: vector<u8>,
        /// Address of the original token on the source chain
        source_token_addr: vector<u8>,
        /// Additional data associated with the transfer
        payload: vector<u8>,
        /// Address receiving the wrapped tokens
        recipient_addr: vector<u8>
    }

    #[event]
    /// Event emitted when the safety level is updated.
    struct SafetyLevelUpdatedEvent has store, drop {
        new_safety_level: u8
    }

    #[event]
    /// Event emitted when the collected fees from the token bridge are withdrawn.
    struct WithdrawCollectedFeeEvent has store, drop {
        deposit_account: address,
        amount: u64,
        wrapped_token_addr: address
    }

    #[event]
    /// Event emitted when the verification strategy is updated.
    struct VerificationStrategyUpdatedEvent has store, drop {
        verification_strategy_type: u8
    }

    #[event]
    /// Event emitted when the token bridge successfully claims a minter capability
    /// for a wrapped token representing a cross-chain asset.
    struct MinterCapClaimedEvent has drop, store {
        /// The address of the admin who initiated the claim
        admin_addr: address,
        /// The original chain ID of the asset
        origin_chain_id: u64,
        /// The original token address (on the source chain)
        origin_token_addr: vector<u8>,
        /// The wrapped token address on the destination chain
        wrapped_token_addr: address,
        /// The address (usually a resource account) that claimed the mint capability, i.e., the bridge signer account.
        claimer_addr: address
    }

    /// Initializes the Token Bridge module with default state.
    /// This function sets up the initial state of the token bridge, including:
    /// - Creating a resource account for the bridge
    /// - Initializing empty data structures for token management
    /// - Setting up the bridge in a paused state for safety
    fun init_module(account: &signer) {
        let (resource_signer, bridge_signer_capability) = account::create_resource_account(account, TOKEN_BRIDGE_SEED);
        move_to(
            &resource_signer,
            TokenBridgeState {
                safety_level: SAFE_LEVEL_DEFAULT,
                verification_strategy_type: FINALITY_VERIFICATION_METHOD,
                is_paused: true,
                admin_addr: signer::address_of(account),
                bridge_signer_capability,
                source_bridge_info: SourceTokenBridgeInfo {
                    bridge_addr: vector::empty(),
                    chain_id: 0
                },
                processed_event_hashes: smart_table::new()
            }
        );
    }

    /// === Admin Functions ===
    /// Updates the verification strategy type for the token bridge.
    ///
    /// - verification_strategy_type: Verification method (SAFE, FINALITY, OPTIMISTIC)
    /// - new_safety_level: The safety level to be used (only applicable for SAFE strategy)
    public entry fun update_verification_strategy_type(
        admin: &signer, verification_strategy_type: u8, new_safety_level: u8
    ) acquires TokenBridgeState {
        let bridge_state = get_token_bridge_state_mut();

        ensure_token_bridge_admin(bridge_state.admin_addr, signer::address_of(admin));

        // Validate and update safety level based on strategy
        assert_and_update_verification_strategy(
            bridge_state, verification_strategy_type, new_safety_level
        );

        bridge_state.verification_strategy_type = verification_strategy_type;

        emit(VerificationStrategyUpdatedEvent { verification_strategy_type });
    }

    /// Updates the pause state of the Token Bridge contract.
    ///
    /// This function allows the bridge admin to pause or unpause the bridge. When the bridge is paused,
    /// certain operations (e.g., token transfers) may be restricted to ensure safety during upgrades or incidents.
    ///
    /// # Arguments
    /// - admin: The signer attempting to modify the pause state (must be bridge admin)
    /// - is_paused: Boolean indicating whether to pause (true) or unpause (false) the bridge
    ///
    /// # Aborts
    /// - If the caller is not the bridge admin
    public entry fun set_token_bridge_pause_state(
        admin: &signer, is_paused: bool
    ) acquires TokenBridgeState {
        let bridge_state = get_token_bridge_state_mut();

        // Ensure the caller matches the stored admin address
        ensure_token_bridge_admin(bridge_state.admin_addr, signer::address_of(admin));

        bridge_state.is_paused = is_paused;

        emit(TokenBridgePauseEvent { is_paused });
    }

    /// Registers a source token bridge from another blockchain.
    ///
    /// This function configures the connection to a token bridge on another chain,
    /// allowing for cross-chain token transfers.
    ///
    /// # Arguments
    /// - admin: The signer of the bridge admin attempting to register the source bridge
    /// - source_token_bridge_addr: The address of the token bridge contract on the source chain (must be 32-byte Ethereum-style padded)
    /// - source_chain_id: The chain ID of the source blockchain
    ///
    /// # Aborts
    /// - If the caller is not the bridge admin
    /// - If the source token bridge address is not 32 bytes long
    public entry fun register_source_token_bridge(
        admin: &signer, source_token_bridge_addr: vector<u8>, source_chain_id: u64
    ) acquires TokenBridgeState {
        let bridge_state = get_token_bridge_state_mut();

        // Check that the caller is the authorized admin
        ensure_token_bridge_admin(bridge_state.admin_addr, signer::address_of(admin));

        // Validate the format of the Ethereum-style padded address
        assert_ethereum_padded_address(&source_token_bridge_addr);

        bridge_state.source_bridge_info.bridge_addr = source_token_bridge_addr;
        bridge_state.source_bridge_info.chain_id = source_chain_id;

        emit(SourceTokenBridgeRegisterEvent { source_token_bridge_addr, source_chain_id });
    }

    /// Removes the registration of a source token bridge from another blockchain.
    ///
    /// This operation disconnects the current chain from the source chains token bridge,
    /// preventing further cross-chain token transfers from that source.
    ///
    /// # Arguments
    /// - admin: The signer of the bridge admin performing the unregistration
    ///
    /// # Aborts
    /// - EUNAUTHORIZED_TOKEN_BRIDGE_ADMIN: If the caller is not the bridge admin
    public entry fun unregister_source_token_bridge(admin: &signer) acquires TokenBridgeState {
        // Load mutable reference to bridge state
        let bridge_state = get_token_bridge_state_mut();

        // Check admin permission
        ensure_token_bridge_admin(bridge_state.admin_addr, signer::address_of(admin));

        let source_token_bridge_addr = bridge_state.source_bridge_info.bridge_addr;
        let source_chain_id = bridge_state.source_bridge_info.chain_id;

        bridge_state.source_bridge_info.bridge_addr = vector::empty();
        bridge_state.source_bridge_info.chain_id = 0;

        emit(
            SourceTokenBridgeUnRegisterEvent { source_token_bridge_addr, source_chain_id }
        );
    }


    /// Allows the bridge admin to withdraw collected fees for a specific wrapped token.
    /// This function transfers the specified amount of fees from the bridges fee store
    /// to the deposit account.
    ///
    /// # Arguments
    /// * account - The signer of the admin attempting to withdraw fees
    /// * deposit_account - The address where the fees will be deposited
    /// * origin_token_address - The address of the original token on its source chain
    /// * origin_token_chain_id - The chain ID where the original token exists
    /// * amount - The amount of fees to withdraw
    ///
    /// # Aborts
    /// * If the caller is not the bridge admin
    /// * If the wrapped token metadata is not found
    /// * If the withdrawal amount exceeds available fees
    ///
    /// # Acquires
    /// * ManagedFungibleAsset - to access transfer capabilities
    /// * TokenBridgeState - to verify admin status and access signer capability
    public entry fun withdraw_collected_fee(
        admin: &signer,
        origin_token_addr: vector<u8>,
        origin_token_chain_id: u64,
        amount: u64
    ) acquires TokenBridgeState {
        // Verify admin privileges
        let bridge_state = get_token_bridge_state_mut();
        ensure_token_bridge_admin(bridge_state.admin_addr, signer::address_of(admin));
        let bridge_address = generate_token_bridge_address();
        let bridge_signer =
            &create_token_bridge_signer(&bridge_state.bridge_signer_capability);

        // Get token metadata and management capabilities
        let (metadata, wrapped_token_addr, _) =
            get_wrapped_token_metadata_and_address(
                origin_token_chain_id, origin_token_addr
            );

        // Ensure fee stores exist and perform transfer
        let deposit_store =
            primary_fungible_store::ensure_primary_store_exists(
                bridge_state.admin_addr, metadata
            );
        let bridge_fee_store =
            primary_fungible_store::ensure_primary_store_exists(
                bridge_address, metadata
            );

        fungible_asset::transfer(
            bridge_signer,
            bridge_fee_store,
            deposit_store,
            amount
        );
        emit(WithdrawCollectedFeeEvent { deposit_account: bridge_state.admin_addr, amount, wrapped_token_addr });
    }

    /// Claims the minter capability for a specific wrapped token tied to a foreign asset.
    /// This is typically invoked by the token bridge admin to enable minting functionality.
    ///
    /// # Arguments
    /// * admin - The signer of the bridge admin invoking this operation
    /// * origin_token_chain_id - The source chain ID of the original token
    /// * origin_token_address - The original tokens address on the source chain
    ///
    /// # Aborts
    /// * EUNAUTHORIZED_BRIDGE_ADMIN - If the caller is not the token bridge admin
    /// * ETOKEN_NOT_REGISTERED - If the wrapped token corresponding to the original asset is not found
    /// * ECAPABILITY_ALREADY_CLAIMED - If the minter capability has already been claimed
    public entry fun claim_minter_capability(
        admin: &signer, origin_token_chain_id: u64, origin_token_addr: vector<u8>
    ) acquires TokenBridgeState {
        // Load bridge state and validate admin rights
        let bridge_state = get_token_bridge_state();
        let admin_addr = signer::address_of(admin);
        ensure_token_bridge_admin(bridge_state.admin_addr, admin_addr);

        // Resolve the wrapped token address based on original token metadata

        let (_, wrapped_token_addr, _) =
            get_wrapped_token_metadata_and_address(origin_token_chain_id, origin_token_addr);
        // Use the bridges signer to claim minting rights for this wrapped token
        let bridge_signer = &create_token_bridge_signer(&bridge_state.bridge_signer_capability);
        claim_minter_capability_for_token(bridge_signer, wrapped_token_addr);
        emit(
            MinterCapClaimedEvent {
                admin_addr,
                origin_chain_id: origin_token_chain_id,
                origin_token_addr,
                wrapped_token_addr,
                claimer_addr: signer::address_of(bridge_signer)
            }
        );
    }

    /// Executes a cross-chain message using the optimistic or safe verification strategy.
    ///
    /// This function verifies a batch of messages using the provided proof data,
    /// ensuring that the event originated from a valid block on the source chain.
    /// It utilizes a light client-based proof validation mechanism.
    ///
    /// Steps:
    /// 1. Constructs a MessageVerification structure.
    /// 2. Processes the batch message data and extracts the event log.
    /// 3. Ensures the event has not been previously executed.
    /// 4. Records the event hash to prevent replay attacks.
    /// 5. Handles the verified event log for further processing.
    ///
    /// Arguments:
    /// 
    /// - account: The signer of the transaction, typically the relayer or bridge operator.
    /// - recent_block_slot: The slot number of the most recent block.
    /// - recent_block_proposer_index: The index of the block proposer in the beacon chain
    /// - recent_block_parent_root: The parent root of the most recent beacon block.
    /// - recent_block_state_root: The state root of the most recent beacon block.
    /// - recent_block_body_root: The body root of the most recent beacon block.
    /// - recent_block_sync_committee_bits: The bit vector representing sync committee participation in the
    ///   most recent block.
    /// - recent_block_sync_committee_signature: The aggregated signature of the sync committee for the
    ///   most recent block.
    /// - recent_block_signature_slot: The slot at which the sync aggregate was signed for the
    ///   most recent block.
    ///
    /// BlockRoots Verification:
    /// - is_historical: Indicates if the block being verified is historical.
    /// - block_roots_index: The index in the block roots vector.
    /// - block_root_proof: The Merkle proof for the block root.
    /// - historical_block_root_proof: The Merkle proof for the historical block root.
    /// - historical_block_summary_root: The summary root of the historical block.
    /// - historical_block_summary_root_proof: The Merkle proof for the historical block summary root.
    /// - historical_block_summary_root_gindex: The generalized index of the historical block summary
    /// - slot, proposer_index, parent_root, state_root, body_root: Details of the target block being verified.
    ///
    /// - tx_index: The index of the transaction in the block.
    /// Receipt Proofs:
    /// - receipts_root_proof: The Merkle proof for the receipts root.
    /// - receipts_root_gindex: The generalized index of the receipts root.
    /// - receipt_proof: The Merkle proof of the receipt within the receipts root.
    /// - receipts_root: The root hash of transaction receipts.
    ///
    /// Cross-Chain Messaging:
    /// - message_id: The unique message identifier.
    /// - source_chain_id: The ID of the source blockchain.
    /// - source_hn_address: The Hypernova contract address on the source chain.
    /// - destination_chain_id: The ID of the destination blockchain.
    /// - destination_hn_address: The Hypernova contract address on the destination chain.
    /// - log_hash: The hash of the event log.
    /// - log_index: The index of the event log in the block.
    ///
    /// Requirements:
    /// - The transaction must be verified against the latest available light client update.
    /// - The event log must not have been previously processed to prevent replay attacks.
    public entry fun execute_optimistic_or_safe(
        account: &signer,
        // Recent Block Parameters
        recent_block_slot: u64,
        recent_block_proposer_index: u64,
        recent_block_parent_root: vector<u8>,
        recent_block_state_root: vector<u8>,
        recent_block_body_root: vector<u8>,
        recent_block_sync_committee_bits: vector<bool>,
        recent_block_sync_committee_signature: vector<u8>,
        recent_block_signature_slot: u64,
        // Historical Parameters
        is_historical: bool,
        block_roots_index: u64,
        block_root_proof: vector<vector<u8>>,
        historical_block_root_proof: vector<vector<u8>>,
        historical_block_summary_root: vector<u8>,
        historical_block_summary_root_proof: vector<vector<u8>>,
        historical_block_summary_root_gindex: u64,
        // Block Header Parameters
        slot: u64,
        proposer_index: u64,
        parent_root: vector<u8>,
        state_root: vector<u8>,
        body_root: vector<u8>,
        // Transaction and Receipt Parameters
        tx_index: u64,
        receipts_root_proof: vector<vector<u8>>,
        receipts_root_gindex: u64,
        receipt_proof: vector<vector<u8>>,
        receipts_root: vector<u8>,
        // Message Parameters
        message_id: vector<u8>,
        source_chain_id: u64,
        source_hn_addr: vector<u8>, //@notice : should be padded 32 bytes from relayer (change in relayer)
        destination_chain_id: u64,
        destination_hn_addr: vector<u8>,
        log_hash: vector<u8>,
        log_index: u64
    ) acquires TokenBridgeState {
        let bridge_state = get_token_bridge_state_mut();

        // 1. Validate bridge state and input parameters
        assert_token_bridge_not_paused(bridge_state.is_paused);
        assert_ethereum_padded_address(&source_hn_addr);

        // 3. Convert addresses to appropriate format
        let src_addr = from_bcs::to_address(source_hn_addr);
        let dst_addr = from_bcs::to_address(destination_hn_addr);

        // 4. Process and verify the message data
        let (extracted_log, extracted_log_hash) =
            process_data_optimistic_or_safe(
                account,
                recent_block_slot,
                recent_block_proposer_index,
                recent_block_parent_root,
                recent_block_state_root,
                recent_block_body_root,
                recent_block_sync_committee_bits,
                recent_block_sync_committee_signature,
                recent_block_signature_slot,
                is_historical,
                block_roots_index,
                block_root_proof,
                historical_block_root_proof,
                historical_block_summary_root,
                historical_block_summary_root_proof,
                historical_block_summary_root_gindex,
                slot,
                proposer_index,
                parent_root,
                state_root,
                body_root,
                tx_index,
                receipts_root_proof,
                receipts_root_gindex,
                receipt_proof,
                receipts_root,
                message_id,
                source_chain_id,
                src_addr,
                destination_chain_id,
                dst_addr,
                log_hash,
                log_index,
                bridge_state.verification_strategy_type,
                bridge_state.safety_level
            );

        // 6. Verify and process the event
        record_executed_event_hash(bridge_state, extracted_log_hash);

        let (relayerReward, token_metadata) =
            process_token_bridge_event(
                &create_token_bridge_signer(&bridge_state.bridge_signer_capability),
                bridge_state.verification_strategy_type,
                bridge_state.safety_level,
                bridge_state.source_bridge_info.chain_id,
                bridge_state.source_bridge_info.bridge_addr,
                extracted_log
            );

        fungible_asset::deposit(
            primary_fungible_store::ensure_primary_store_exists(
                signer::address_of(account), token_metadata
            ),
            relayerReward
        );
        emit(ExecutionEvent { log_index, message_id, extracted_log_hash });
    }


    /// Executes a finality-based verification of a cross-chain message and processes the event log.
    ///
    /// This function validates a batch of messages using a finality-proof mechanism, ensuring that
    /// the provided proof data corresponds to a finalized block on the source chain. It enforces
    /// stricter verification than optimistic methods.
    ///
    /// # Steps
    /// 1. Constructs a verification structure using process_data_finality.
    /// 2. Extracts the event log from the batch message data.
    /// 3. Checks that the event has not been previously executed (prevents replay attacks).
    /// 4. Records the event hash to avoid re-execution.
    /// 5. Processes the verified event log further via process_token_bridge_event.
    ///
    /// # Arguments
    /// - recent_block_slot: Slot number of the attested beacon block header.
    /// - recent_block_proposer_index: Index of the block proposer.
    /// - recent_block_parent_root: Parent root hash of the attested beacon block.
    /// - recent_block_state_root: State root hash of the attested beacon block.
    /// - recent_block_body_root: Body root hash of the attested beacon block.
    /// - recent_block_slot_finalized: Slot number of the finalized beacon block header.
    /// - recent_block_proposer_index_finalized: Proposer index of the finalized block.
    /// - recent_block_parent_root_finalized: Parent root of the finalized beacon block.
    /// - recent_block_state_root_finalized: State root of the finalized beacon block.
    /// - recent_block_body_root_finalized: Body root of the finalized beacon block.
    /// - recent_block_finality_branch: Merkle proof for finality verification.
    /// - recent_block_sync_committee_bits: Bit vector of sync committee participation.
    /// - recent_block_sync_committee_signature: Aggregated signature from sync committee.
    /// - recent_block_signature_slot: Slot at which the sync aggregate was signed.
    ///
    /// # BlockRoots Verification
    /// - is_historical: Whether the block being verified is historical.
    /// - block_roots_index: Index in the block roots vector.
    /// - block_root_proof: Merkle proof for the block root.
    /// - historical_block_root_proof: Additional proofs for historical roots.
    /// - historical_block_summary_root: Summary root of the historical block.
    /// - historical_block_summary_root_proof: Merkle proof for the summary root.
    /// - historical_block_summary_root_gindex: Generalized index of the summary root.
    /// - slot, proposer_index, parent_root, state_root, body_root: Details of the target block.
    ///
    /// # Receipt Proofs
    /// - tx_index: Transaction index in the block.
    /// - receipts_root_proof: Merkle proof for the receipts root.
    /// - receipts_root_gindex: Generalized index of the receipts root.
    /// - receipt_proof: Merkle proof of the receipt within the receipts root.
    /// - receipts_root: Root hash of transaction receipts.
    ///
    /// # Cross-Chain Messaging
    /// - message_id: Unique identifier for the message.
    /// - source_chain_id: ID of the source blockchain.
    /// - source_hn_addr: Hypernova contract address on the source chain (32-byte padded).
    /// - destination_chain_id: ID of the destination blockchain.
    /// - destination_hn_addr: Hypernova contract address on the destination chain.
    /// - log_hash: Hash of the event log.
    /// - log_index: Index of the event log within the block.
    ///
    /// # Execution Flow
    /// 1. Converts 20-byte Ethereum addresses to 32-byte format using from_bcs::to_address.
    /// 2. Calls process_data_finality to perform message verification and extract the event log.
    /// 3. Checks that the event log has not been processed before (prevents replay).
    /// 4. Records the event hash in the bridge state.
    /// 5. Processes the verified event via process_token_bridge_event.
    /// 6. Emits an ExecutionEvent recording the execution details.
    ///
    /// # Requirements
    /// - Event logs must not be processed more than once.
    /// - Extracted logs must exist before processing.

    public entry fun execute_finality(
        account: &signer,
        // attested_header: BeaconBlockHeader,
        recent_block_slot: u64,
        recent_block_proposer_index: u64,
        recent_block_parent_root: vector<u8>,
        recent_block_state_root: vector<u8>,
        recent_block_body_root: vector<u8>,
        // finalized_header: BeaconBlockHeader,
        recent_block_slot_finalized: u64,
        recent_block_proposer_index_finalized: u64,
        recent_block_parent_root_finalized: vector<u8>,
        recent_block_state_root_finalized: vector<u8>,
        recent_block_body_root_finalized: vector<u8>,
        recent_block_finality_branch: vector<vector<u8>>,
        // sync_aggregate: SyncAggregate,
        recent_block_sync_committee_bits: vector<bool>,
        recent_block_sync_committee_signature: vector<u8>,
        recent_block_signature_slot: u64,
        // BlockRoots
        is_historical: bool,
        block_roots_index: u64,
        block_root_proof: vector<vector<u8>>,
        // Historical_Roots
        historical_block_root_proof: vector<vector<u8>>,
        historical_block_summary_root: vector<u8>,
        historical_block_summary_root_proof: vector<vector<u8>>,
        historical_block_summary_root_gindex: u64,
        slot: u64,
        proposer_index: u64,
        parent_root: vector<u8>,
        state_root: vector<u8>,
        body_root: vector<u8>,
        tx_index: u64,
        receipts_root_proof: vector<vector<u8>>,
        receipts_root_gindex: u64,
        receipt_proof: vector<vector<u8>>,
        receipts_root: vector<u8>,
        message_id: vector<u8>,
        source_chain_id: u64,
        source_hn_addr: vector<u8>, //@notice : should be padded 32 bytes from relayer (change in relayer)
        destination_chain_id: u64,
        destination_hn_addr: vector<u8>,
        log_hash: vector<u8>,
        log_index: u64
    ) acquires TokenBridgeState {
        let bridge_state = get_token_bridge_state_mut();

        // 1. Validate bridge state and input parameters
        assert_token_bridge_not_paused(bridge_state.is_paused);
        assert_ethereum_padded_address(&source_hn_addr);

        // 3. Convert addresses to appropriate format
        let src_addr = from_bcs::to_address(source_hn_addr);
        let dst_addr = from_bcs::to_address(destination_hn_addr);

        let (extracted_log, extracted_log_hash) =
            process_data_finality(
                account,
                recent_block_slot,
                recent_block_proposer_index,
                recent_block_parent_root,
                recent_block_state_root,
                recent_block_body_root,
                recent_block_slot_finalized,
                recent_block_proposer_index_finalized,
                recent_block_parent_root_finalized,
                recent_block_state_root_finalized,
                recent_block_body_root_finalized,
                recent_block_finality_branch,
                recent_block_sync_committee_bits,
                recent_block_sync_committee_signature,
                recent_block_signature_slot,
                is_historical,
                block_roots_index,
                block_root_proof,
                historical_block_root_proof,
                historical_block_summary_root,
                historical_block_summary_root_proof,
                historical_block_summary_root_gindex,
                slot,
                proposer_index,
                parent_root,
                state_root,
                body_root,
                tx_index,
                receipts_root_proof,
                receipts_root_gindex,
                receipt_proof,
                receipts_root,
                message_id,
                source_chain_id,
                src_addr,
                destination_chain_id,
                dst_addr,
                log_hash,
                log_index,
                bridge_state.verification_strategy_type
            );

        // 6. Verify and process the event
        record_executed_event_hash(bridge_state, extracted_log_hash);

        let (relayerReward, token_metadata) =
            process_token_bridge_event(
                &create_token_bridge_signer(&bridge_state.bridge_signer_capability),
                bridge_state.verification_strategy_type,
                bridge_state.safety_level,
                bridge_state.source_bridge_info.chain_id,
                bridge_state.source_bridge_info.bridge_addr,
                extracted_log
            );

        fungible_asset::deposit(
            primary_fungible_store::ensure_primary_store_exists(
                signer::address_of(account), token_metadata
            ),
            relayerReward
        );

        // 7. Emit execution event
        emit(ExecutionEvent { log_index, message_id, extracted_log_hash });
    }

    // === Private Functions ===

    /// checks if the provided source token bridge address is a valid Ethereum-style padded address.
    inline fun assert_ethereum_padded_address(
        source_token_bridge_address: &vector<u8>
    ) {
        assert!(
            vector::length(source_token_bridge_address) == ETHEREUM_PADDED_ADDRESS_LEN,
            EINVALID_SOURCE_TOKEN_BRIDGE_ADDRESS
        );
    }

    /// Asserts that the token bridge is not currently paused.
    inline fun assert_token_bridge_not_paused(paused: bool) {
        assert!(!paused, ETOKEN_BRIDGE_PAUSED);
    }

    /// Asserts that the provided safety level is above minimum safety level.
    inline fun assert_min_safety_level(safety_level: u8) {
        assert!(
            safety_level >= MIN_SAFETY_LEVEL,
            EINVALID_SAFETY_LEVEL
        );
    }

    /// Asserts and updates the verification strategy type and safety level in the TokenBridgeState.
    inline fun assert_and_update_verification_strategy(
        state: &mut TokenBridgeState, strategy_type: u8, new_safety_level: u8
    ) {
        // Ensure the strategy type is within allowed range
        assert!(
            strategy_type >= MIN_VERIFICATION_STRATEGY_TYPE
                && strategy_type <= MAX_VERIFICATION_STRATEGY_TYPE,
            EINVALID_VERIFICATION_STRATEGY_TYPE_RANGE
        );

        // Handle strategy-specific safety level assignment
        if (strategy_type == FINALITY_VERIFICATION_METHOD
            || strategy_type == OPTIMISTIC_VERIFICATION_METHOD) {
            state.safety_level = SAFE_LEVEL_DEFAULT;
            emit(SafetyLevelUpdatedEvent { new_safety_level: SAFE_LEVEL_DEFAULT });
        } else {
            assert_min_safety_level(new_safety_level);
            state.safety_level = new_safety_level;
            emit(SafetyLevelUpdatedEvent { new_safety_level });
        }
    }

    /// Checks if the given account has admin privileges for the Token Bridge.
    ///
    /// # Arguments
    /// * account - The signer whose admin status is being verified
    ///
    /// # Returns
    /// * true if the account has the admin privileges for the Token Bridge.
    /// * false otherwise
    inline fun ensure_token_bridge_admin(
        stored_admin_addr: address, admin_addr: address
    ) acquires TokenBridgeState {
        assert!(
            stored_admin_addr == admin_addr,
            EUNAUTHORIZED_TOKEN_BRIDGE_ADMIN
        );
    }

    /// Returns a mutable reference to the TokenBridgeState.
    inline fun get_token_bridge_state_mut(): &mut TokenBridgeState acquires TokenBridgeState {
        borrow_global_mut<TokenBridgeState>(generate_token_bridge_address())
    }

    /// Returns an immutable reference to the TokenBridgeState.
    inline fun get_token_bridge_state(): &TokenBridgeState acquires TokenBridgeState {
        borrow_global<TokenBridgeState>(generate_token_bridge_address())
    }

    /// Creates a signer for the Token Bridge contract operations.
    /// Uses the stored signer capability from TokenBridgeState to generate
    /// an authenticated signer for privileged operations.
    ///
    /// Returns:
    /// - A signer object associated with the Token Bridge.
    fun create_token_bridge_signer(signer_cap: &SignerCapability): signer {
        account::create_signer_with_capability(signer_cap)
    }

    /// Stores an event hash to prevent replay attacks.
    /// Adds the hash to the processed_event_hashes vector in TokenBridgeState
    /// to ensure the same event cannot be processed twice.
    ///
    /// # Arguments
    /// * hash - The unique event hash to be recorded
    ///
    /// # Acquires
    /// * TokenBridgeState - to update the processed_event_hashes
    fun record_executed_event_hash(
        state: &mut TokenBridgeState, hash: vector<u8>
    ) {
        let processed_event_hashes = &mut state.processed_event_hashes;
        assert!(
            !smart_table::contains(processed_event_hashes, hash),
            EEVENT_ALREADY_EXECUTED
        );
        smart_table::add(processed_event_hashes, hash, true);
    }

    /// Processes a bridge event log and handles the cross-chain token transfer.
    /// This function extracts transaction details from the log, verifies the source bridge,
    /// and mints wrapped tokens for the recipient.
    ///
    /// # Arguments
    /// * token_bridge_signer - The signer of the token bridge resource account
    /// * verification_strategy_type - The verification strategy type (SAFE, FINALITY, OPTIMISTIC)
    /// * safety_level - The safety level for the verification strategy
    /// * registered_chain_id - The chain ID of the registered source token bridge
    /// * registered_bridge_addr - The expected address of the source token bridge (32-byte padded)
    /// * extracted_log - The log event containing the bridge transaction details
    ///
    /// # Aborts
    /// * ESOURCE_BRIDGE_ADDRESS_MISMATCH - If the source bridge address doesnt match the expected address
    /// * EINVALID_MESSAGE_DATA_SIZE - If the message data size is invalid
    /// * ESOURCE_BRIDGE_CHAIN_ID_MISMATCH - If the source chain ID doesnt match the expected chain ID
    fun process_token_bridge_event(
        token_bridge_signer: &signer,
        verification_strategy_type: u8,
        safety_level: u8,
        registered_chain_id: u64,
        registered_bridge_addr: vector<u8>,
        extracted_log: ExtractedLog
    ): (FungibleAsset, Object<Metadata>) {
        // Extract and verify source bridge information
        let event_topics = get_topics(&extracted_log);
        assert!(
            vector::length(event_topics) >= NUM_EVENT_TOPICS,
            EINVALID_EVENT_TOPICS_LENGTH
        );
        let source_bridge_addr = *vector::borrow(event_topics, 1);
        let message_id = *vector::borrow(event_topics, 2);

        assert!(
            registered_bridge_addr == source_bridge_addr,
            ESOURCE_BRIDGE_ADDRESS_MISMATCH
        );

        // Extract and validate message data
        let message_data = get_data(&extracted_log);
        assert!(
            vector::length(message_data) == MESSAGE_DATA_SIZE,
            EINVALID_MESSAGE_DATA_SIZE
        );

        // Parse sender and token information
        let (sender_addr, source_token_addr, source_chain_id_bytes) =
            parse_header_fields(message_data);

        let source_chain_id = bytes_to_u64(source_chain_id_bytes);


        assert!(
            source_chain_id == registered_chain_id,
            ESOURCE_BRIDGE_CHAIN_ID_MISMATCH
        );
        let (_, wrapped_token_addr, token_identifier) =
            get_wrapped_token_metadata_and_address(source_chain_id, source_token_addr);

        assert!(
            is_token_active(token_identifier),
            ETOKEN_NOT_ACTIVE
        );
        let (
            transfer_payload,
            final_amount,
            bridge_service_fee,
            relayer_reward,
            recipient_addr
        ) = parse_transfer_details(message_data);

        // Get wrapped token address and process transfer
        let (total_amount_fa, token_metadata) =
            mint_wrapped_token(
                token_bridge_signer, //the resource account of the bridge which hold the signer cap
                wrapped_token_addr,
                token_identifier,
                final_amount + bridge_service_fee
            );
        assert!(bridge_service_fee >= relayer_reward, EINVALID_FEES);
        let bridge_service_fee_minted = fungible_asset::extract(
            &mut total_amount_fa,
            (bridge_service_fee - relayer_reward)
        );
        let relayer_reward_minted =
            fungible_asset::extract(&mut total_amount_fa, relayer_reward);
        fungible_asset::deposit(
            primary_fungible_store::ensure_primary_store_exists(
                from_bcs::to_address(recipient_addr),
                token_metadata
            ),
            total_amount_fa
        );
        fungible_asset::deposit(
            primary_fungible_store::ensure_primary_store_exists(
                signer::address_of(token_bridge_signer),
                token_metadata
            ),
            bridge_service_fee_minted
        );

        emit(
            ExtractedMessageDataEvent {
                verification_strategy_type,
                safety_level,
                amount: final_amount,
                bridge_service_fee,
                relayer_reward,
                dest_chain_id: chain_id::get(),
                dest_block_height: block::get_current_block_height(),
                dest_timestamp: timestamp::now_seconds(),
                dest_token_addr: wrapped_token_addr,
                source_chain_id,
                message_id,
                source_token_bridge_addr: source_bridge_addr,
                sender_addr,
                source_token_addr,
                payload: transfer_payload,
                recipient_addr
            }
        );
        (relayer_reward_minted, token_metadata)
    }

    /// Parses the transfer-related fields from the message_data.
    ///
    /// Expects message_data to be at least 288 bytes long, and slices the data to extract:
    /// - transfer_payload: bytes from offset 160 to 192
    /// - final_amount: u64 from offset 192 to 224
    /// - fee_cut_to_service: u64 from offset 224 to 256
    /// - relayer_reward: u64 from offset 256 to 288
    /// - recipient_address: bytes from offset 288 to 320
    ///
    /// # Parameters
    /// - message_data: A reference to the serialized message data vector.
    ///
    /// # Returns
    /// A tuple containing:
    /// - transfer_payload: vector<u8>
    /// - final_amount: u64
    /// - fee_cut_to_service: u64
    /// - relayer_reward: u64
    /// - recipient_address: vector<u8>
    fun parse_transfer_details(message_data: &vector<u8>):
    (vector<u8>, u64, u64, u64, vector<u8>) {
        let transfer_payload = vector::slice(message_data, TRANSFER_PAYLOAD_START, TRANSFER_PAYLOAD_END);
        let final_amount = bytes_to_u64(vector::slice(message_data, FINAL_AMOUNT_START, FINAL_AMOUNT_END));
        let fee_cut_to_service = bytes_to_u64(vector::slice(message_data, FEE_CUT_START, FEE_CUT_END));
        let relayer_reward = bytes_to_u64(vector::slice(message_data, RELAYER_REWARD_START, RELAYER_REWARD_END));
        let recipient_addr = vector::slice(message_data, RECIPIENT_ADDR_START, RECIPIENT_ADDR_END);
        (
            transfer_payload,
            final_amount,
            fee_cut_to_service,
            relayer_reward,
            recipient_addr
        )
    }

    /// Parses the header-related fields from the message_data.
    ///
    /// Expects message_data to be at least 160 bytes long, and slices the data to extract:
    /// - sender_address: bytes from offset 64 to 96
    /// - source_token_address: bytes from offset 96 to 128
    /// - source_chain_id_bytes: bytes from offset 128 to 160
    ///
    /// # Parameters
    /// - message_data: A reference to the serialized message data vector.
    ///
    /// # Returns
    /// A tuple containing:
    /// - sender_addr: vector<u8>
    /// - source_token_addr: vector<u8>
    /// - source_chain_id_bytes: vector<u8>
    fun parse_header_fields(message_data: &vector<u8>): (vector<u8>, vector<u8>, vector<u8>) {
        let senderAddr = vector::slice(message_data, SENDER_ADDR_START, SENDER_ADDR_END);
        let source_token_addr = vector::slice(message_data, SOURCE_TOKEN_ADDR_START, SOURCE_TOKEN_ADDR_END);
        let source_chain_id_bytes = vector::slice(message_data, SOURCE_CHAIN_ID_START, SOURCE_CHAIN_ID_END);

        (senderAddr, source_token_addr, source_chain_id_bytes)
    }

    // === View Functions ===

    #[view]
    public fun get_verification_method_and_safety_level(): VerificationInfo acquires TokenBridgeState {
        let state = get_token_bridge_state();
        VerificationInfo {
            verification_strategy_type: state.verification_strategy_type,
            safety_level: state.safety_level,
        }
    }

    #[view]
    /// Generates the deterministic resource address for the Token Bridge contract.
    /// This address is used to store the bridges state and is derived from the
    /// module address and a constant seed.
    public fun generate_token_bridge_address(): address {
        account::create_resource_address(&@token_bridge_service, TOKEN_BRIDGE_SEED)
    }

    #[view]
    /// Checks if the Token Bridge is currently paused.
    ///
    /// This function reads the TokenBridgeState to determine whether bridge operations are paused.
    ///
    /// Returns:
    /// - true if the token bridge is paused.
    /// - false otherwise.
    public fun is_token_bridge_paused(): bool acquires TokenBridgeState {
        get_token_bridge_state().is_paused
    }

    #[view]
    /// Checks if an event hash has already been executed.
    ///
    /// Arguments:
    /// - hash: A reference to the event hash to check.
    ///
    /// Returns:
    /// - true if the hash has been recorded (i.e., the event has been executed).
    /// - false otherwise.
    public fun has_executed_event_hash(hash: vector<u8>): bool acquires TokenBridgeState {
        let processed_event_hashes = &get_token_bridge_state().processed_event_hashes;
        smart_table::contains(processed_event_hashes, hash)
    }

    #[view]
    /// Retrieves the metadata of a wrapped token based on its origin information.
    ///
    /// This function looks up the wrapped tokens metadata by checking the stored
    /// mapping of original token addresses and chain IDs to their corresponding wrapped assets.
    ///
    /// Arguments:
    /// - origin_token_address: The address of the original token on the source chain.
    /// - origin_token_chain_id: The chain ID of the original token.
    ///
    /// Returns:
    /// - An Object<Metadata> containing the metadata of the wrapped token.
    public fun get_wrapped_token_metadata_and_address(
        source_chain_id: u64, source_token_address: vector<u8>
    ): (Object<Metadata>, address, vector<u8>) {
        let token_identifier =
            generate_token_identifier_hash(source_chain_id, source_token_address);
        let wrapped_token_address = get_wrapped_token_address(token_identifier);
        (
            object::address_to_object<Metadata>(wrapped_token_address),
            wrapped_token_address,
            token_identifier
        )
    }

    #[view]
    /// Retrieves the source token bridge address and its chain ID.
    ///
    /// Returns:
    /// - A tuple containing the source token bridge address (vector<u8>) and the source chain ID (u64).
    public fun get_source_token_bridge_info(): SourceBridgeInfo acquires TokenBridgeState {
        let source_info = &get_token_bridge_state().source_bridge_info;
        SourceBridgeInfo {
            bridge_address: source_info.bridge_addr,
            chain_id: source_info.chain_id,
        }
    }

    #[view]
    /// Retrieves the Admin Address of Token Bridge
    ///
    /// Returns:
    ///  - Address of Token Bridge admin.
    public fun get_admin_address(): address acquires TokenBridgeState {
        get_token_bridge_state().admin_addr
    }


    #[view]
    /// Retrieves the balance of wrapped tokens for a specific recipient.
    /// This function gets the balance of tokens that were bridged from another chain
    /// and are now held by the specified address.
    ///
    /// # Arguments
    /// * origin_token_address - The address of the original token on its source chain
    /// * origin_token_chain_id - The chain ID where the original token exists
    /// * receiver_address - The address to check the balance for
    ///
    /// Returns:1
    /// - The balance of the wrapped token as a u64.
    public fun balance_view(
        origin_token_address: vector<u8>,
        origin_token_chain_id: u64,
        receiver_address: address
    ): u64 {
        // Get the wrapped token metadata
        let (metadata, _, _) =
            get_wrapped_token_metadata_and_address(
                origin_token_chain_id, origin_token_address
            );

        // Ensure the receiver has a store and get their balance
        let receiver_store =
            primary_fungible_store::ensure_primary_store_exists(
                receiver_address, metadata
            );

        balance(receiver_store)
    }

    #[view]
    /// Retrieves the balance of wrapped tokens for a specific recipient.
    /// This function gets the balance of tokens that were bridged from another chain
    /// and are now held by the specified address.
    ///
    /// # Arguments
    /// * origin_token_address - The address of the original token on its source chain
    /// * origin_token_chain_id - The chain ID where the original token exists
    ///
    /// Returns:
    /// - The balance of the wrapped token as a u64.
    public fun get_total_collected_fees(
        origin_token_address: vector<u8>, origin_token_chain_id: u64
    ): u64 {
        // Get the wrapped token metadata
        let (metadata, _, _) =
            get_wrapped_token_metadata_and_address(
                origin_token_chain_id, origin_token_address
            );

        let receiver_address = generate_token_bridge_address();

        let receiver_store =
            primary_fungible_store::ensure_primary_store_exists(
                receiver_address, metadata
            );

        balance(receiver_store)
    }


    // === Test only Functions ===
    #[test_only]
    /// View function to extract fields from SourceBridgeInfo.
    public fun get_source_bridge_info_view(info: SourceBridgeInfo): (vector<u8>, u64) {
        (info.bridge_address, info.chain_id)
    }

    #[test_only]
    /// View function to extract fields from VerificationInfo.
    public fun get_verification_info_view(info: VerificationInfo): (u8, u8) {
        (info.verification_strategy_type, info.safety_level)
    }


    #[test_only]
    public fun init_module_test(account: &signer) {
        init_module(account)
    }

    #[test_only]
    public fun test_record_executed_event_hash(hash: vector<u8>) acquires TokenBridgeState {
        let state = get_token_bridge_state_mut();
        record_executed_event_hash(state, hash)
    }

    #[test_only]
    public fun test_create_token_bridge_signer(): signer acquires TokenBridgeState {
        let signer_cap = &get_token_bridge_state_mut().bridge_signer_capability;
        account::create_signer_with_capability(signer_cap)
    }


    #[test_only]
    public fun test_process_token_bridge_event(
        token_bridge_signer: &signer,
        verification_strategy_type: u8,
        safety_level: u8,
        registered_chain_id: u64,
        registered_bridge_addr: vector<u8>,
        extracted_log: ExtractedLog
    ): (FungibleAsset, Object<Metadata>) {
        process_token_bridge_event(
            token_bridge_signer,
            verification_strategy_type,
            safety_level,
            registered_chain_id,
            registered_bridge_addr,
            extracted_log
        )
    }

}
