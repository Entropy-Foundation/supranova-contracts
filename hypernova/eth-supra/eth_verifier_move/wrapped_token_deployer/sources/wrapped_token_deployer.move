module wrapped_token_deployer::wrapped_token_deployer {
    use std::signer;
    use std::string::String;
    use std::vector;
    use std::option;
    use std::bcs;
    use std::hash::sha2_256;
    use aptos_std::smart_table::{Self, SmartTable};
    use supra_framework::account::{Self, SignerCapability};
    use supra_framework::object::{Self, Object};
    use supra_framework::event::emit;
    use supra_framework::primary_fungible_store;
    use supra_framework::fungible_asset::{
        Self,
        amount,
        MintRef,
        TransferRef,
        BurnRef,
        Metadata,
        FungibleAsset
    };


    // === Wrapped Token Deployer Errors ===

    /// 0000: The wrapped token deployer is currently paused. Operations are temporarily disabled.
    const EWRAPPED_TOKEN_DEPLOYER_PAUSED: u64 = 0000;

    /// 0001: Unauthorized access attempt by a non-admin. Only wrapped token deployer admins may perform this action.
    const EUNAUTHORIZED_WRAPPED_TOKEN_DEPLOYER_ADMIN: u64 = 0001;

    /// 0002: The requested wrapped token does not exist in the registry.
    const EWRAPPED_TOKEN_DOES_NOT_EXIST: u64 = 0002;

    /// 0003: The token is already listed in the registry and cannot be re-registered.
    const ETOKEN_ALREADY_LISTED: u64 = 0003;

    /// 0004: The token is delisted and cannot be used in minting or other operations.
    const ETOKEN_DE_LISTED: u64 = 0004;

    /// 0005: The token has never been registered and cannot be operated on.
    const ETOKEN_NOT_REGISTERED: u64 = 0005;

    /// 0006: The wrapped token address provided does not match the registered address.
    const EWRAPPED_TOKEN_ADDRESS_MISMATCH: u64 = 0006;

    /// 0007: The caller is not authorized to mint the wrapped token.
    const EUNAUTHORIZED_WRAPPED_TOKEN: u64 = 0007;

    /// 0008: Minter capability already exists for the given signer.
    const EMINTER_CAP_ALREADY_EXISTS: u64 = 0008;

    /// 0009: Minter capability was not found for the given signer.
    const EMINTER_CAP_NOT_FOUND: u64 = 0009;

    /// 0010: The specified wrapped token is not found in the signers minter capability list.
    const ETOKEN_NOT_FOUND_IN_MINTER_CAP: u64 = 0010;

    /// 0011: The caller is not whitelisted to mint wrapped tokens.
    const EMINTER_NOT_WHITELISTED: u64 = 0011;

    /// 0012: The caller is already whitelisted to mint wrapped tokens.
    const EMINTER_ALREADY_WHITELISTED: u64 = 0012;

    /// 0013: The signer is not authorized to access the fungible asset metadata object.
    const EUNAUTHORIZED_FUNGIBLE_ASSET_ACCESS: u64 = 0013;

    /// 0014: The mint amount must be non-zero. Zero-value minting is not allowed.
    const EZERO_MINT_AMOUNT_NOT_ALLOWED: u64 = 0014;

    /// 0015: The provided address length is invalid. Expected length is 32 bytes.
    const EINVALID_ADDRESS_LEN: u64 = 0015;

    /// 0016: The wrapped token has not yet been added to the whitelist mapping
    const EWRAPPED_TOKEN_NOT_ADDED: u64 = 0016;


    // === Constants ===

    ///  Seed value used as a unique namespace for the wrapped token deployer object.
    ///  This ensures deterministic address derivation for  wrapped token deployer  resources.
    const WRAPPED_TOKEN_DEPLOYER_SEED: vector<u8> = b"ETH_SUPRA_WRAPPED_TOKEN_DEPLOYER_SEED";

    /// The fixed length (in bytes) of  address when padded to fit a 32-byte word.
    const ORIGIN_TOKEN_ADDRESS_LEN: u64 = 32;

    /// Emitted in the event when the token is listed
    const TOKEN_LISTED: u8 = 1;

    /// Emitted in the event when the token is delisted
    const TOKEN_DELISTED: u8 = 0;

    // === Structs ===

    #[resource_group_member(group = supra_framework::object::ObjectGroup)]
    /// Stores the global state for managing wrapped tokens in the cross-chain bridge system.
    ///
    /// This resource is used to control and maintain the state of wrapped token operations,
    /// including pausing functionality, administrative access, signer capabilities for minting,
    /// whitelisted minter authorization, and metadata about wrapped tokens.
    struct WrappedTokensState has key {
        /// A boolean flag indicating whether the wrapped token operations are paused.
        ///   This is useful for emergency halts or maintenance.
        is_paused: bool,
        ///The address of the administrator who has control over this wrapped token state.
        admin_addr: address,
        /// A signer capability that allows the designated entity
        ///   to perform privileged actions such as minting wrapped tokens.
        wrapped_tokens_signer_capability: SignerCapability,
        /// A smart table that maps token identifiers (hashes)
        ///   to the authorized minter addresses. Only these addresses can mint wrapped tokens for
        ///   the corresponding token identifier.
        whitelisted_minter_identifiers: SmartTable<address, vector<address>>,
        ///A smart table that maps token identifiers (hashes) to
        ///WrapperInfo structs, which hold metadata and configuration about each wrapped token.
        token_wrappers_map: SmartTable<vector<u8>, WrapperInfo>
    }

    #[resource_group_member(group = supra_framework::object::ObjectGroup)]
    /// Manages minting, transferring, and burning operations for fungible assets.
    /// This struct holds the necessary references to perform core token operations
    struct ManagedFungibleAsset has key {
        /// Reference required for minting new tokens
        mint_ref: MintRef,
        /// Reference required for transferring tokens between accounts
        transfer_ref: TransferRef,
        /// Reference required for burning (destroying) tokens
        burn_ref: BurnRef
    }

    #[resource_group_member(group = supra_framework::object::ObjectGroup)]
    /// Capability that allows a whitelisted minter to mint specific wrapped tokens.
    /// Each minter is granted permission to mint a subset of wrapped tokens.
    struct MinterCapability has key, drop {
        /// List of wrapped token addresses the minter is authorized to mint.
        wrapped_token_addresses: vector<address>
    }

    /// Stores metadata about a registered wrapped token.
    struct WrapperInfo has store, copy {
        /// The chain ID of the tokens original chain before being wrapped.
        token_origin_chain_id: u64,

        /// Address of the wrapped token contract deployed on the current chain.
        wrapped_token_addr: address,

        /// Flag indicating whether the token is actively listed (true) or delisted (false).
        /// Tokens cannot be removed from storage due to being named objects, so this flag enables soft deletion.
        is_listed: bool,

        /// The address of the original token on the source chain, encoded as bytes.
        /// Used to uniquely identify the token across chains.
        token_origin_addr: vector<u8>,
    }


    /// Represents a unique pairing of a minter and a wrapped token.
    ///
    /// This struct is used to identify and hash whitelist relationships between
    /// a specific minter and a specific wrapped token. The structure is serialized
    /// and hashed to produce a unique identifier used in permission validation and storage.
    struct MinterIdentifierInfo has drop {
        /// The address of the wrapped token the minter is associated with.
        token_addr: address,
        /// The address of the minter authorized to mint the wrapped token.
        minter_addr: address
    }

    /// Information about a tokens origin on its source chain.
    ///
    /// # Overview
    /// Contains the essential identifiers needed to uniquely identify
    /// a token from its source blockchain.
    ///
    /// # Fields
    /// - chain_id: Identifier of the source blockchain
    /// - token_addr: Contract address of the token on source chain
    struct OriginTokenInfo has drop {
        chain_id: u64,
        token_addr: vector<u8>
    }


    /// Struct representing the original source chain and address of a wrapped token.
    struct WrappedTokenOrigin has copy, drop, store {
        /// The chain ID where the token originally resides.
        chain_id: u64,

        /// The original address of the token on its source chain.
        token_addr: vector<u8>,
    }

    //====== Events ======

    #[event]
    /// Event emitted when the wrapped token deployer is paused or unpaused.
    struct WrappedTokenDeployerPauseEvent has drop, store {
        // Indicates whether the wrapped token deployer was paused (true) or resumed (false).
        is_paused: bool
    }


    #[event]
    /// Event emitted when a token is delisted or relisted from the wrapped token deployer.
    struct TokenListingUpdateEvent has drop, store {
        /// Unique token identifier.
        token_identifier: vector<u8>,
        /// The address of the listed/delisted wrapped token.
        wrapped_token_addr: address,
        /// Action type.
        ///TOKEN_DELISTED : 0 for TOKEN_LISTED, 1
        action_type: u8
    }


    #[event]
    /// Event emitted when a new wrapped token is registered through the wrapped token deployer.
    struct WrappedTokenRegisterEvent has store, drop {
        /// Number of decimals the token uses.
        decimals: u8,
        /// Name of the wrapped token.
        name: String,
        /// Symbol (ticker) of the wrapped token.
        symbol: String,
        /// URI pointing to the icon or logo of the token.
        icon_uri: String,
        /// URI pointing to the projects website or documentation.
        project_uri: String,
        /// On-chain address of the deployed wrapped token.
        wrapped_token_addr: address,
        /// Unique identifier representing the source chain and token address.
        token_identifier: vector<u8>
    }

    #[event]
    /// Event emitted when a new minter is added to the whitelist.
    struct MinterWhitelistedEvent has drop, store {
        /// Address of the whitelisted minter.
        minter_addr: address,
        /// Address of the wrapped token this minter is authorized for.
        wrapped_token_addr: address
    }

    #[event]
    /// Event emitted when a minter is removed from the whitelist.
    struct MinterRemovedFromWhitelistEvent has drop, store {
        /// Address of the removed minter.
        minter_addr: address,
        /// Token address that the minter was deauthorized for.
        wrapped_token_addr: address
    }

    #[event]
    /// Event emitted when a whitelisted minter claims their capability.
    struct MinterCapClaimedEvent has drop, store {
        /// Address of the minter who claimed the capability.
        minter_addr: address,
        /// Address of the wrapped token.
        wrapped_token_addr: address
    }

    #[event]
    /// Event emitted when a wrapped token is removed from a minters capability.
    struct TokenRemovedFromMinterCapEvent has drop, store {
        /// Address of the affected minter.
        minter_addr: address,
        /// Address of the wrapped token that was removed.
        wrapped_token_addr: address
    }

    #[event]
    /// Event emitted when an entire minter capability is removed.
    struct MinterCapRemovedEvent has drop, store {
        /// Address of the minter whose capability was removed.
        minter_addr: address
    }

    #[event]
    /// Event emitted when wrapped tokens are minted by an authorized minter.
    struct WrappedTokenMintedEvent has drop, store {
        /// Amount of tokens minted.
        amount: u64,
        /// Address of the minter who performed the mint.
        minter_addr: address,
        /// Address of the wrapped token.
        wrapped_token_addr: address
    }

    /// This function sets up the initial state , including:
    /// - Creating a resource account for the Wrapped Token Deployer
    /// - Initializing empty data structures for Wrapped token state
    /// - Setting up the Wrepped token deployer in a paused state for safety
    fun init_module(account: &signer) {
        let (resource_signer, wrapped_tokens_signer_capability) =
            account::create_resource_account(account, WRAPPED_TOKEN_DEPLOYER_SEED);

        move_to(
            &resource_signer,
            WrappedTokensState {
                is_paused: false,
                admin_addr: signer::address_of(account),
                wrapped_tokens_signer_capability,
                whitelisted_minter_identifiers: smart_table::new(),
                token_wrappers_map: smart_table::new()
            }
        );
    }

    // === Admin Functions ===

    /// Updates the pause state of the wrapped token deployer.
    /// Only the wrapped token deployer admin can call this function to enable or disable the pause state.
    /// When paused, certain wrapped token deployer operation like minting are restricted.
    ///
    /// # Arguments
    /// * account - The signer attempting to modify the pause state (must be wrapped token deployer admin).
    /// * is_paused - Boolean flag to set pause state: true to pause, false to unpause.
    ///
    /// # Aborts
    /// * If the caller is not the wrapped token deployer admin.
    public entry fun set_wrapped_token_deployer_pause_state(
        admin: &signer, is_paused: bool
    ) acquires WrappedTokensState {
        let state = get_wrapped_tokens_state_mut();

        ensure_wrapped_token_deployer_admin(state.admin_addr, signer::address_of(admin));

        state.is_paused = is_paused;

        emit(WrappedTokenDeployerPauseEvent { is_paused });
    }


    /// Adds a minter address to the whitelist for a specific wrapped token.
    /// Only the wrapped token deployer admin can whitelist a minter.
    /// This allows the whitelisted minter to later claim minting capabilities for the token.
    ///
    /// If the wrapped token has not been registered in the whitelist mapping,
    /// it is initialized with the given minter address.
    ///
    /// # Arguments
    /// * admin - The signer with wrapped token deployer admin privileges.
    /// * minter_addr - The address of the minter to whitelist.
    /// * wrapped_token_addr - The wrapped token address that the minter will be authorized for.
    ///
    /// # Aborts
    /// * EMINTER_ALREADY_WHITELISTED - If the minter is already whitelisted for the given token.
    /// * If the caller is not the wrapped token deployer admin.
    public entry fun whitelist_minter_for_token(
        admin: &signer, minter_addr: address, wrapped_token_addr: address
    ) acquires WrappedTokensState {
        let state = get_wrapped_tokens_state_mut();

        ensure_wrapped_token_deployer_admin(state.admin_addr, signer::address_of(admin));

        let whitelisted_minter_identifiers = &mut state.whitelisted_minter_identifiers;


        if (!smart_table::contains(whitelisted_minter_identifiers, wrapped_token_addr))
            {
                smart_table::add(whitelisted_minter_identifiers, wrapped_token_addr, vector::singleton(minter_addr));
                emit(
                    MinterWhitelistedEvent {
                        minter_addr,
                        wrapped_token_addr
                    });
                return
            };

        let whitelisted_addrs = smart_table::borrow_mut(whitelisted_minter_identifiers, wrapped_token_addr);

        assert!(
            !vector::contains(
                whitelisted_addrs,
                &minter_addr
            ),
            EMINTER_ALREADY_WHITELISTED
        );

        vector::push_back(
            whitelisted_addrs,
            minter_addr
        );
        emit(
            MinterWhitelistedEvent {
                minter_addr,
                wrapped_token_addr
            }
        )
    }

    /// Removes a minter from the whitelist for a specific wrapped token.
    /// Only the wrapped token deployer admin can remove a minter from the whitelist.
    ///
    /// # Arguments
    /// * admin - The signer with wrapped token deployer admin privileges.
    /// * minter_addr - The address of the minter to remove.
    /// * wrapped_token_addr - The wrapped token address associated with the minter.
    ///
    /// # Aborts
    /// * EWRAPPED_TOKEN_NOT_ADDED - If the wrapped token has not yet been added to the whitelist mapping.
    /// * EMINTER_NOT_WHITELISTED - If the minter is not currently whitelisted for the given wrapped token.
    /// * If the caller is not the wrapped token deployer admin.
    public entry fun remove_whitelisted_minter(
        admin: &signer, minter_addr: address, wrapped_token_addr: address
    ) acquires WrappedTokensState {
        let state = get_wrapped_tokens_state_mut();
        ensure_wrapped_token_deployer_admin(state.admin_addr, signer::address_of(admin));
        remove_minter_from_whitelist(state, wrapped_token_addr, minter_addr);

        emit(
            MinterRemovedFromWhitelistEvent { minter_addr, wrapped_token_addr }
        )
    }


    /// Removes a specific wrapped token from a minters capability list.
    /// Only the wrapped token deployer admin can revoke a minters minting rights for a token.
    ///
    /// # Arguments
    /// * account - The signer with wrapped token deployer admin privileges.
    /// * minter_addr - The address of the minter whose capability will be modified.
    /// * token_address - The wrapped token address to remove from the minters capability.
    ///
    /// # Aborts
    /// * If the caller is not the wrapped token deployer admin.
    /// * If the specified minter capability resource does not exist.
    public entry fun remove_wrapped_token_from_minter_cap(
        admin: &signer, minter_addr: address, wrapped_token_addr: address
    ) acquires MinterCapability, WrappedTokensState {
        ensure_wrapped_token_deployer_admin(
            get_wrapped_tokens_state().admin_addr, signer::address_of(admin)
        );
        ensure_mint_cap_exists(minter_addr);
        let cap = borrow_global_mut<MinterCapability>(minter_addr);

        assert!(
            vector::contains(&cap.wrapped_token_addresses, &wrapped_token_addr),
            ETOKEN_NOT_FOUND_IN_MINTER_CAP
        );
        vector::remove_value(&mut cap.wrapped_token_addresses, &wrapped_token_addr);

        emit(
            TokenRemovedFromMinterCapEvent { minter_addr, wrapped_token_addr }
        )
    }

    /// Completely revokes and removes the minting capability resource from a minter.
    /// Only the wrapped token deployer admin can remove a minters entire mint capability.
    ///
    /// # Arguments
    /// * account - The signer with wrapped token deployer admin privileges.
    /// * minter_addr - The address of the minter whose minting capability will be removed.
    ///
    /// # Aborts
    /// * If the caller is not the wrapped token deployer admin.
    /// * If the specified minter capability resource does not exist.
    public entry fun remove_minter_capability(
        admin: &signer, minter_addr: address
    ) acquires MinterCapability, WrappedTokensState {
        ensure_wrapped_token_deployer_admin(
            get_wrapped_tokens_state().admin_addr, signer::address_of(admin)
        );
        ensure_mint_cap_exists(minter_addr);

        let _ = move_from<MinterCapability>(minter_addr);
        emit(MinterCapRemovedEvent { minter_addr })
    }

    /// Registers a new wrapped token in the wrapped token deployer system.
    /// Creates a wrapped version of a token from another chain with the specified metadata.
    ///
    /// # Arguments
    /// * account - The admin account registering the token
    /// * source_token_address - The address of the original token (must be 32 bytes padded)
    /// * source_chain_id - The chain ID where the original token exists
    /// * decimals - The number of decimal places for the token
    /// * name - The name of the token
    /// * symbol - The symbol/ticker of the token
    /// * icon_uri - URI pointing to the tokens icon
    /// * project_uri - URI pointing to the tokens project information
    ///
    /// # Aborts
    /// * If the caller is not the wrapped token deployer admin
    /// * If the source token address length is invalid
    public entry fun create_wrapped_token(
        admin: &signer,
        decimals: u8,
        name: String,
        symbol: String,
        icon_uri: String,
        project_uri: String,
        token_origin_chain_id: u64,
        token_origin_addr: vector<u8>
    ) acquires WrappedTokensState {
        ensure_wrapped_token_deployer_admin(
            get_wrapped_tokens_state().admin_addr,
            signer::address_of(admin)
        );
        //Initialize the wrapped token
        initialize_wrapped_token(
            &create_wrapped_tokens_signer(),
            decimals,
            name,
            symbol,
            icon_uri,
            project_uri,
            token_origin_chain_id,
            token_origin_addr
        );
    }

    /// Delists (unregisters) a wrapped token from the wrapped token deployer system.
    /// This marks the wrapped token as inactive, preventing any further operations such as minting or transfers through the wrapped token deployer.
    ///
    /// # Arguments
    /// * account - The admin signer authorized to perform the delisting.
    /// * token_identifier - The unique identifier of the wrapped token in the wrapped token deployer system.
    ///
    /// # Aborts
    /// * EUNAUTHORIZED_WRAPPED_TOKEN_DEPLOYER_ADMIN - If the caller is not the wrapped token deployer admin.
    /// * ETOKEN_NOT_REGISTERED - If the token is not registered in the wrapped token deployer.
    /// * ETOKEN_DE_LISTED - If the token is already delisted (inactive).
    ///
    /// # Events
    /// Emits TokenListingUpdateEvent with:
    /// * token_identifier - The unique token identifier delisted.
    /// * wrapped_token_address - The address of the wrapped token.
    /// * action_type : TOKEN_DELISTED
    public entry fun delist_wrapped_token(
        admin: &signer, token_identifier: vector<u8>
    ) acquires WrappedTokensState {
        let admin_addr = signer::address_of(admin);
        let state = get_wrapped_tokens_state_mut();

        ensure_wrapped_token_deployer_admin(state.admin_addr, admin_addr);

        ensure_token_identifier_exists(state, token_identifier);

        let token_info =
            smart_table::borrow_mut(&mut state.token_wrappers_map, token_identifier);

        assert!(token_info.is_listed, ETOKEN_DE_LISTED);

        token_info.is_listed = false;

        emit(
            TokenListingUpdateEvent {
                token_identifier,
                wrapped_token_addr: token_info.wrapped_token_addr,
                action_type: TOKEN_DELISTED
            }
        );
    }

    /// Allows a whitelisted minter to claim their minting capability for a wrapped token.
    /// Once claimed, the minter can mint the specified wrapped token.
    /// Claiming removes the minter from the whitelist to prevent duplicate claims.
    ///
    /// # Arguments
    /// * account - The signer claiming the minter capability.
    /// * wrapped_token_address - The wrapped token address for which to claim minting rights.
    ///
    /// # Aborts
    /// * If the caller is not whitelisted for the token.
    /// * If the caller already holds minting capability for the token.
    public fun claim_minter_capability_for_token(
        account: &signer, wrapped_token_addr: address
    ) acquires MinterCapability, WrappedTokensState {
        let minter_addr = signer::address_of(account);

        remove_minter_from_whitelist(get_wrapped_tokens_state_mut(), wrapped_token_addr, minter_addr);
        // Initialize capability resource if not exists
        if (!exists<MinterCapability>(minter_addr)) {
            move_to(account, MinterCapability { wrapped_token_addresses: vector::empty() });
        };

        let cap = borrow_global_mut<MinterCapability>(minter_addr);
        assert!(
            !vector::contains(&cap.wrapped_token_addresses, &wrapped_token_addr),
            EMINTER_CAP_ALREADY_EXISTS
        );
        vector::push_back(&mut cap.wrapped_token_addresses, wrapped_token_addr);

        emit(MinterCapClaimedEvent { minter_addr, wrapped_token_addr })
    }


    /// Mints wrapped tokens to a recipient for a token originally from another chain.
    ///
    /// This function is used to mint the wrapped version of a token on the destination chain.
    /// It verifies the tokens registration status, validates the minters authorization, and uses the mint
    /// capability to produce the specified amount of wrapped tokens.
    ///
    /// # Arguments
    /// * account - The signer (minter authorized to mint wrapped tokens.
    /// * wrapped_token_address - The address of the wrapped token on the destination chain.
    /// * token_identifier - The unique identifier used to track the wrapped token (typically derived from source chain metadata).
    /// * amount - The number of tokens to mint.
    ///
    /// # Returns
    /// * A tuple containing:
    ///   - FungibleAsset: The newly minted token.
    ///   - Object<Metadata>: The metadata object associated with the wrapped token.
    ///
    /// # Aborts
    /// * EWRAPPED_TOKEN_DEPLOYER_PAUSED - If the wrapped token deployer is paused.
    /// * EWRAPPED_TOKEN_ADDRESS_MISMATCH - If the given wrapped_token_address does not match the registered one.
    /// * ETOKEN_DE_LISTED - If the token is currently delisted and not eligible for minting.
    /// * EUNAUTHORIZED_WRAPPED_TOKEN - If the signer is not authorized to mint this token.

    public fun mint_wrapped_token(
        account: &signer,
        wrapped_token_addr: address,
        token_identifier: vector<u8>,
        amount: u64
    ): (FungibleAsset, Object<Metadata>) acquires MinterCapability, ManagedFungibleAsset, WrappedTokensState {
        assert!(amount != 0, EZERO_MINT_AMOUNT_NOT_ALLOWED);
        let minter_addr = signer::address_of(account);
        ensure_mint_cap_exists(minter_addr);
        let state = get_wrapped_tokens_state();
        assert!(!state.is_paused, EWRAPPED_TOKEN_DEPLOYER_PAUSED);

        ensure_token_identifier_exists(state, token_identifier);

        let info = smart_table::borrow(&state.token_wrappers_map, token_identifier);

        // Ensure correct wrapped token address and active listing
        assert!(
            info.wrapped_token_addr == wrapped_token_addr,
            EWRAPPED_TOKEN_ADDRESS_MISMATCH
        );
        assert!(info.is_listed, ETOKEN_DE_LISTED);


        let cap = borrow_global<MinterCapability>(minter_addr);
        assert!(
            vector::contains(&cap.wrapped_token_addresses, &wrapped_token_addr),
            EUNAUTHORIZED_WRAPPED_TOKEN
        );

        let token_metadata = object::address_to_object<Metadata>(wrapped_token_addr);
        let managed_fa = get_authorized_fungible_asset(&create_wrapped_tokens_signer(), token_metadata);

        let total_minted_fa = fungible_asset::mint(&managed_fa.mint_ref, amount);

        emit(
            WrappedTokenMintedEvent {
                amount: amount(&total_minted_fa),
                minter_addr,
                wrapped_token_addr
            }
        );

        (total_minted_fa, token_metadata)
    }

    // === Private Functions ===
    /// Removes a whitelisted minter address from the whitelist of a specific wrapped token.
    ///
    /// This internal utility function checks if the wrapped token has been initialized
    /// in the whitelist mapping and ensures that the given minter is currently whitelisted.
    ///
    /// # Arguments
    /// * state - Mutable reference to the global WrappedTokensState.
    /// * wrapped_token_addr - The address of the wrapped token whose whitelist is being modified.
    /// * minter_addr - The address of the minter to remove from the whitelist.
    ///
    /// # Aborts
    /// * EWRAPPED_TOKEN_NOT_ADDED - If the wrapped token has not been added to the whitelist mapping.
    /// * EMINTER_NOT_WHITELISTED - If the minter is not currently whitelisted for the specified token.
    fun remove_minter_from_whitelist(
        state: &mut WrappedTokensState, wrapped_token_addr: address, minter_addr: address
    ) {
        let whitelisted_minter_identifiers = &mut state.whitelisted_minter_identifiers;

        assert!(
            smart_table::contains(whitelisted_minter_identifiers, wrapped_token_addr),
            EWRAPPED_TOKEN_NOT_ADDED
        );
        let whitelisted_addrs = smart_table::borrow_mut(whitelisted_minter_identifiers, wrapped_token_addr);

        let (exists, index) = vector::index_of(whitelisted_addrs, &minter_addr);

        assert!(
            exists,
            EMINTER_NOT_WHITELISTED
        );

        vector::remove(whitelisted_addrs, index);
    }

    /// Deploys a new wrapped fungible asset (FA) token with the given metadata and stores its management capabilities.
    ///
    /// This function handles the creation of the wrapped token on-chain by:
    /// 1. Creating a named object representing the token.
    /// 2. Initializing the fungible asset with the specified metadata (name, symbol, decimals, icon, project URI).
    /// 3. Generating mint, burn, and transfer capabilities for the token.
    /// 4. Storing these capabilities in a ManagedFungibleAsset resource under the tokens signer.
    ///
    /// # Arguments
    /// * fa_signer - The signer authorized to deploy the token.
    /// * token_identifier - A unique byte vector identifier for the token (used to create the named object).
    /// * decimals - Number of decimals for the tokens precision.
    /// * name - Human-readable token name.
    /// * symbol - Token symbol.
    /// * icon_uri - URI pointing to the token icon.
    /// * project_uri - URI pointing to the token/project information.
    ///
    /// # Returns
    /// The blockchain address of the newly deployed wrapped token.
    ///
    /// # Notes
    /// This function does not register the token in any wrapped token deployer state; it only deploys the token and stores capabilities.

    fun deploy_wrapped_token_and_store_caps(
        fa_signer: &signer,
        token_identifier: vector<u8>,
        decimals: u8,
        name: String,
        symbol: String,
        icon_uri: String,
        project_uri: String
    ): address {
        let token_constructor_ref =
            &object::create_named_object(fa_signer, token_identifier);

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            token_constructor_ref,
            option::none(),
            name,
            symbol,
            decimals,
            icon_uri,
            project_uri
        );

        let token_signer = object::generate_signer(token_constructor_ref);
        let mint_capability = fungible_asset::generate_mint_ref(token_constructor_ref);
        let burn_capability = fungible_asset::generate_burn_ref(token_constructor_ref);
        let transfer_capability =
            fungible_asset::generate_transfer_ref(token_constructor_ref);

        // Store management capabilities
        move_to(
            &token_signer,
            ManagedFungibleAsset {
                mint_ref: mint_capability,
                transfer_ref: transfer_capability,
                burn_ref: burn_capability
            }
        );

        object::address_from_constructor_ref(token_constructor_ref)
    }

    /// Initializes and registers a wrapped fungible asset (FA) token in the wrapped token deployer system.
    ///
    /// This function either:
    /// 1. Registers a new wrapped token: Deploys a wrapped FA using metadata and stores management capabilities.
    /// 2. Relists a previously delisted token: If the token already exists in the registry but is marked inactive, it reactivates it and emits a relisting event.
    ///
    /// # Arguments
    /// * fa_signer - Signer responsible for deploying and managing the wrapped token.
    /// * decimals - Number of decimal places for the token.
    /// * name - Name of the wrapped token.
    /// * symbol - Symbol representing the wrapped token.
    /// * icon_uri - URI pointing to the tokens icon.
    /// * project_uri - URI for the associated project or token metadata.
    /// * token_identifier - A unique identifier for the token, typically derived from source chain + asset data.
    ///
    /// # Behavior
    /// - If the token is already active (is_listed = true), the function aborts.
    /// - If the token exists but was delisted (is_listed = false), it is relisted, and a TokenListingUpdateEvent is emitted.
    /// - If the token is new, it is deployed and added to the registry, and a WrappedTokenRegisterEvent is emitted.
    ///
    /// # Aborts
    /// * ETOKEN_ALREADY_LISTED - If the token is already active and registered.
    ///
    /// # Emits
    /// * TokenListingUpdateEvent - When an inactive token is reactivated.
    /// * WrappedTokenRegisterEvent - When a new token is deployed and registered.

    fun initialize_wrapped_token(
        fa_signer: &signer,
        decimals: u8,
        name: String,
        symbol: String,
        icon_uri: String,
        project_uri: String,
        token_origin_chain_id: u64,
        token_origin_addr: vector<u8>
    ) acquires WrappedTokensState {
        let state = get_wrapped_tokens_state_mut();
        let token_identifier = generate_token_identifier_hash(token_origin_chain_id, token_origin_addr);
        // Checks if a token with the given token_identifier is already registered in the wrapped token deployer state.
        // - If the token is currently active (is_listed == true), this function aborts with ETOKEN_ALREADY_LISTED.
        // - If the token exists but is inactive (is_listed == false), it reactivates the token by setting is_listed to true,
        //   emits a TokenListingUpdateEvent, and returns early to avoid redeployment.
        if (smart_table::contains(&state.token_wrappers_map, token_identifier)) {
            let info =
                smart_table::borrow_mut(&mut state.token_wrappers_map, token_identifier);
            assert!(!info.is_listed, ETOKEN_ALREADY_LISTED);
            info.is_listed = true;

            emit(
                TokenListingUpdateEvent {
                    token_identifier,
                    wrapped_token_addr: info.wrapped_token_addr,
                    action_type: TOKEN_LISTED
                }
            );
            return
        };
        let wrapped_token_addr = deploy_wrapped_token_and_store_caps(
            fa_signer,
            token_identifier,
            decimals,
            name,
            symbol,
            icon_uri,
            project_uri
        );

        smart_table::add(
            &mut state.token_wrappers_map,
            token_identifier,
            WrapperInfo { token_origin_chain_id, wrapped_token_addr, is_listed: true, token_origin_addr }
        );

        emit(
            WrappedTokenRegisterEvent {
                name,
                decimals,
                symbol,
                icon_uri,
                project_uri,
                wrapped_token_addr,
                token_identifier
            }
        );
    }

    /// Creates a signer for the wrapped token deployer contract operations.
    /// Uses the stored signer capability from WrappedTokensState to generate
    /// an authenticated signer for privileged operations.
    ///
    /// Returns:
    /// - A signer object associated with the wrapped token deployer.
    fun create_wrapped_tokens_signer(): signer acquires WrappedTokensState {
        account::create_signer_with_capability(
            &get_wrapped_tokens_state().wrapped_tokens_signer_capability
        )
    }

    /// Asserts that the provided address is correctly padded to the expected fixed length (32 bytes).
    ///
    /// This ensures consistency in cross-chain address representations by requiring all addresses
    /// to conform to the standard ORIGIN_TOKEN_ADDRESS_LEN.
    ///
    /// Aborts with EINVALID_ADDRESS_LEN if the address length does not match ORIGIN_TOKEN_ADDRESS_LEN.
    inline fun assert_padded_address(
        addr: &vector<u8>
    ) {
        assert!(
            vector::length(addr) == ORIGIN_TOKEN_ADDRESS_LEN,
            EINVALID_ADDRESS_LEN
        );
    }

    /// Ensures that the caller is the authorized wrapped token deployer admin.
    ///
    /// # Parameters
    /// * expected_admin - The address of the authorized admin stored during initialization.
    /// * caller - The address of the signer attempting the operation.
    ///
    /// # Aborts
    /// * EUNAUTHORIZED_WRAPPED_TOKEN_DEPLOYER_ADMIN - If the caller is not the authorized admin.
    inline fun ensure_wrapped_token_deployer_admin(
        expected_admin: address, caller: address
    ) {
        assert!(
            expected_admin == caller,
            EUNAUTHORIZED_WRAPPED_TOKEN_DEPLOYER_ADMIN
        );
    }


    /// checks if the given token identifier exists in the wrapped tokens state.
    inline fun ensure_token_identifier_exists(
        state: &WrappedTokensState, token_identifier: vector<u8>
    ) {
        assert!(
            smart_table::contains(&state.token_wrappers_map, token_identifier),
            ETOKEN_NOT_REGISTERED
        );
    }

    /// Returns a mutable reference to the WrappedTokensState.
    inline fun get_wrapped_tokens_state_mut(): &mut WrappedTokensState acquires WrappedTokensState {
        borrow_global_mut<WrappedTokensState>(generate_wrapped_token_deployer_address())
    }

    /// Returns an immutable reference to the WrappedTokensState.
    inline fun get_wrapped_tokens_state(): &WrappedTokensState acquires WrappedTokensState {
        borrow_global<WrappedTokensState>(generate_wrapped_token_deployer_address())
    }

    /// Checks if a minter capability exists for the given address.
    inline fun ensure_mint_cap_exists(minter_addr: address) {
        assert!(exists<MinterCapability>(minter_addr), EMINTER_CAP_NOT_FOUND);
    }


    /// Retrieves an authorized fungible asset object associated with an owner.
    ///
    /// Arguments:
    /// - owner: A reference to the signer who owns the asset.
    /// - asset_metadata: The metadata object representing the asset.
    ///
    /// Returns:
    /// - A reference to the ManagedFungibleAsset object.
    ///
    /// Requirements:
    /// - The provided signer must be the owner of the asset.
    inline fun get_authorized_fungible_asset(
        owner: &signer, asset_metadata: Object<Metadata>
    ): &ManagedFungibleAsset acquires ManagedFungibleAsset {
        assert!(
            object::is_owner(asset_metadata, signer::address_of(owner)),
            EUNAUTHORIZED_FUNGIBLE_ASSET_ACCESS
        );
        borrow_global<ManagedFungibleAsset>(object::object_address(&asset_metadata))
    }


    // === View Functions ===

    #[view]
    /// Retrieves a list of all token identifiers registered in the wrapped token registry.
    ///
    /// Returns:
    /// - vector<vector<u8>>: A list of unique token identifiers used as keys in the registry.
    ///   Each identifier typically encodes information like the origin chain ID and original token address.
    ///
    /// This function is useful for off-chain systems or dashboards to enumerate all known wrapped tokens
    /// and fetch further details using get_origin_token_info.
    public fun get_token_identifiers(): vector<vector<u8>> acquires WrappedTokensState {
        let origin_token_info_list = &get_wrapped_tokens_state().token_wrappers_map;
        smart_table::keys(origin_token_info_list)
    }

    #[view]
    /// Retrieves the origin chain ID and original token address for a given token identifier.
    ///
    /// Arguments:
    /// - token_identifier: A unique identifier for a wrapped token, typically derived from
    ///   the tokens original chain ID and source address.
    ///
    /// Returns:
    /// - A tuple containing:
    ///   - u64: The chain ID where the token originated.
    ///   - vector<u8>: The original address of the token on its source chain.
    ///
    /// Aborts with ETOKEN_NOT_REGISTERED if the token identifier does not exist in the registry.
    public fun get_origin_token_info(token_identifier: vector<u8>): WrappedTokenOrigin acquires WrappedTokensState {
        let token_wrappers_map = &get_wrapped_tokens_state().token_wrappers_map;
        assert!(smart_table::contains(token_wrappers_map, token_identifier), ETOKEN_NOT_REGISTERED);
        let wrapped_info = smart_table::borrow(token_wrappers_map, token_identifier);
        WrappedTokenOrigin {
            chain_id: wrapped_info.token_origin_chain_id,
            token_addr: wrapped_info.token_origin_addr,
        }
    }


    #[view]
    /// Generates a unique hash for a token using its origin chain ID and token address.
    ///
    /// This function creates a OriginTokenInfo struct using the provided chain_id and token_addr,
    /// serializes it using BCS encoding, and computes a SHA-256 hash of the serialized bytes.
    /// The resulting hash serves as a unique identifier for the token across chains.
    ///
    /// # Parameters
    /// - chain_id: The original chain ID where the token was deployed.
    /// - token_addr: The original token address as a byte vector.
    ///
    /// # Returns
    /// A SHA-256 hash (as a vector<u8>) representing the unique identifier of the token.
    ///
    /// # Example
    ///
    /// let hash = generate_token_identifier_hash(1, b"0x123...");
    ///
    public fun generate_token_identifier_hash(
        chain_id: u64, token_addr: vector<u8>
    ): vector<u8> {
        assert_padded_address(&token_addr);
        let token_identifier = OriginTokenInfo { chain_id, token_addr };
        let bytes = bcs::to_bytes(&token_identifier);
        sha2_256(bytes)
    }

    #[view]
    /// Generates a unique identifier hash used to represent a (minter, token) whitelist pair.
    ///
    /// This identifier is derived by serializing a MinterIdentifierInfo struct using BCS,
    /// and then hashing the resulting byte array with SHA2-256. It can be used to index or
    /// validate whitelist entries in a consistent and collision-resistant way.
    ///
    /// # Arguments
    /// * minter_addr - The address of the whitelisted minter.
    /// * token_addr - The address of the wrapped token the minter is authorized for.
    ///
    /// # Returns
    /// * A vector<u8> representing the SHA2-256 hash of the BCS-serialized identifier.
    public fun generate_whitelist_identifier_hash(
        minter_addr: address, token_addr: address
    ): vector<u8> {
        let minter_identifier = MinterIdentifierInfo { token_addr, minter_addr };
        let bytes = bcs::to_bytes(&minter_identifier);
        sha2_256(bytes)
    }

    #[view]
    /// Retrieves the capabilities of a specific minter.
    /// This function returns a list of wrapped token addresses that the minter is authorized to mint.
    /// If the minter does not have any capabilities, it returns an empty vector.
    /// # Arguments
    /// * minter: The address of the minter whose capabilities are being queried.
    ///
    /// # Returns
    /// * vector<address>: A vector containing the addresses of wrapped tokens that the minter can mint.
    ///   If the minter has no capabilities, an empty vector is returned.
    public fun get_minter_capabilities(minter: address): vector<address> acquires MinterCapability {
        if (!exists<MinterCapability>(minter)) {
            vector::empty()
        } else {
            let cap = borrow_global<MinterCapability>(minter);
            cap.wrapped_token_addresses
        }
    }

    #[view]
    /// Generates the deterministic resource address for the wrapped token deployer contract.
    /// This address is used to store the wrapped token deployer state and is derived from the
    /// module address and a constant seed.
    public fun generate_wrapped_token_deployer_address(): address {
        account::create_resource_address(
            &@wrapped_token_deployer, WRAPPED_TOKEN_DEPLOYER_SEED
        )
    }

    #[view]
    /// Checks if the wrapped token deployer is currently paused.
    ///
    /// This function reads the WrappedTokensState to determine whether wrapped token deployer operations are paused.
    ///
    /// Returns:
    /// - true if the wrapped token deployer is paused.
    /// - false otherwise.
    public fun is_wrapped_tokens_deployer_paused(): bool acquires WrappedTokensState {
        get_wrapped_tokens_state().is_paused
    }

    #[view]
    /// Retrieves the Admin Address of Wrapped Token Deployer
    ///
    /// Returns:
    ///  - Address of wrapped token deployer admin.
    public fun get_admin_address(): address acquires WrappedTokensState {
        get_wrapped_tokens_state().admin_addr
    }

    #[view]
    /// Checks if a token is currently registered in the wrapped token deployer system.
    /// A token is considered registered if it exists in the token registration smart_table.
    ///
    /// # Arguments
    /// * source_token_address - The address of the token on the source chain
    /// * source_chain_id - The chain ID of the source blockchain
    ///
    /// # Returns
    /// * true if the token is registered
    /// * false if the token is not registered
    public fun is_token_registered(token_identifier: vector<u8>): bool acquires WrappedTokensState {
        let wrapped_token_deployer_address = generate_wrapped_token_deployer_address();
        let state = borrow_global_mut<WrappedTokensState>(wrapped_token_deployer_address);
        smart_table::contains(&state.token_wrappers_map, token_identifier)
    }

    #[view]
    /// Checks if a token is currently active in the wrapped token deployer system.
    /// A token is considered active if it is registered and not marked as unregistered.
    ///
    /// # Arguments
    /// * source_token_address - The address of the token on the source chain
    /// * source_chain_id - The chain ID of the source blockchain
    ///
    /// # Returns
    /// * true if the token is registered and active
    /// * false if the token is not registered or has been unregistered
    public fun is_token_active(token_identifier: vector<u8>): bool acquires WrappedTokensState {
        let state = get_wrapped_tokens_state_mut();
        if (!smart_table::contains(&state.token_wrappers_map, token_identifier)) {
            return false
        };
        smart_table::borrow(&state.token_wrappers_map, token_identifier).is_listed
    }


    #[view]
    /// Checks if a specific minter address is whitelisted for a given wrapped token.
    ///
    /// # Arguments
    /// * wrapped_token_addr - The address of the wrapped token.
    /// * minter_addr - The address of the minter to check.
    ///
    /// # Returns
    /// * true if the minter address is whitelisted for the specified wrapped token.
    /// * false otherwise.
    public fun is_minter_whitelisted(
        wrapped_token_addr: address,
        minter_addr: address
    ): bool acquires WrappedTokensState {
        let whitelisted_minter_identifiers = &get_wrapped_tokens_state().whitelisted_minter_identifiers;

        if (!smart_table::contains(whitelisted_minter_identifiers, wrapped_token_addr)) {
            return false
        };
        let whitelisted_addrs = smart_table::borrow(whitelisted_minter_identifiers, wrapped_token_addr);

        if (!vector::contains(whitelisted_addrs, &minter_addr)) {
            return false
        };
        true
    }

    #[view]
    /// Retrieves the address of a wrapped token based on its source token details.
    ///
    /// Arguments:
    /// - token_identifier: A vector<u8> representing the unique identifier of the token.
    ///
    /// Returns:
    /// - The address of the corresponding wrapped token.
    public fun get_wrapped_token_address(
        token_identifier: vector<u8>
    ): address acquires WrappedTokensState {
        let token_wrappers_map = &get_wrapped_tokens_state().token_wrappers_map;
        assert!(
            smart_table::contains(token_wrappers_map, token_identifier),
            EWRAPPED_TOKEN_DOES_NOT_EXIST
        );
        smart_table::borrow(token_wrappers_map, token_identifier).wrapped_token_addr
    }


    //==== Tests_only functions=======
    #[test_only]
    use std::string;

    #[test_only]
    public fun test_init_module(admin: &signer) {
        init_module(admin);
    }


    #[test_only]
    public fun test_exists(resource_addr: address) {
        exists<WrappedTokensState>(resource_addr);
    }

    #[test_only]
    public fun test_ensure_mint_cap_exists(minter_addr: address) {
        ensure_mint_cap_exists(minter_addr)
    }

    #[test_only]
    public fun test_only_set_wrapped_token_deployer_config(
        admin: &signer, minter: &signer, origin_token_chain_id: u64, token_addr: vector<u8>
    ): address acquires WrappedTokensState {
        init_module(admin);
        set_wrapped_token_deployer_pause_state(admin, false);
        assert!(!is_wrapped_tokens_deployer_paused(), 222);
        let minter_addr = signer::address_of(minter);

        create_wrapped_token(
            admin,
            18,
            string::utf8(b"Wrapped ETH"),
            string::utf8(b"WETH"),
            string::utf8(b"https://supra.com"),
            string::utf8(b"https://supra.com"),
            origin_token_chain_id,
            token_addr
        );
        let tokenIdentifier = generate_token_identifier_hash(origin_token_chain_id, token_addr);
        let wrapped_token_address = get_wrapped_token_address(tokenIdentifier);

        whitelist_minter_for_token(admin, minter_addr, wrapped_token_address);


        assert!(is_minter_whitelisted(wrapped_token_address, minter_addr), 222);
        // claim_minter_capability_for_token(minter, wrapped_token_address);
        // ensure_mint_cap_exists(minter_addr);

        wrapped_token_address
    }

}
