#[test_only]
module wrapped_token_deployer::wrapped_token_deployer_test {
    use wrapped_token_deployer::wrapped_token_deployer::{
        is_token_active,
        is_token_registered,
        delist_wrapped_token,
        remove_minter_capability,
        remove_wrapped_token_from_minter_cap,
        get_minter_capabilities,
        generate_wrapped_token_deployer_address,
        test_exists,
        get_admin_address,
        remove_whitelisted_minter,
        test_ensure_mint_cap_exists,
        create_wrapped_token,
        get_token_identifiers,
        mint_wrapped_token,
        claim_minter_capability_for_token,
        is_minter_whitelisted,
        whitelist_minter_for_token,
        get_wrapped_token_address,
        generate_token_identifier_hash,
        is_wrapped_tokens_deployer_paused,
        test_init_module,
        set_wrapped_token_deployer_pause_state
    };
    use std::signer::{Self, address_of};
    use std::string;
    use std::vector;
    use supra_framework::primary_fungible_store;
    use supra_framework::fungible_asset::{
        amount,
        deposit
    };
    use supra_framework::account;

    #[test(admin = @0xdeadbeef2, minter = @0x222)]
    fun test_wrapped_token_deployer_end_to_end(
        admin: &signer, minter: &signer
    ) {
        test_init_module(admin);
        set_wrapped_token_deployer_pause_state(admin, false);
        assert!(!is_wrapped_tokens_deployer_paused(), 222);
        let minter_addr = signer::address_of(minter);
        let _chain_id = 1;
        let source_token_address =
            x"000000000000000000000000fff9976782d46cc05630d1f6ebab18b2324d6b14";
        let tokenIdentifier = generate_token_identifier_hash(1, source_token_address);

        create_wrapped_token(
            admin,
            0,
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            1,
            source_token_address
        );

        let wrapped_token_address = get_wrapped_token_address(tokenIdentifier);

        whitelist_minter_for_token(admin, minter_addr, wrapped_token_address);

        assert!(is_minter_whitelisted(wrapped_token_address, minter_addr), 222);

        claim_minter_capability_for_token(minter, wrapped_token_address);
        test_ensure_mint_cap_exists(minter_addr);

        let (minted_fa, token_metadata) =
            mint_wrapped_token(
                minter,
                wrapped_token_address,
                tokenIdentifier,
                10000
            );

        assert!(amount(&minted_fa) == 10000, 22);
        let token_identifiers = get_token_identifiers();
        assert!(vector::pop_back(&mut token_identifiers) == tokenIdentifier, 22);
        deposit(
            primary_fungible_store::ensure_primary_store_exists(
                minter_addr, token_metadata
            ),
            minted_fa
        );
    }

    #[test(admin = @0xdeadbeef2, _minter = @0x222)]
    fun test_init_modules(admin: &signer, _minter: &signer) {
        test_init_module(admin);

        let resource_addr = generate_wrapped_token_deployer_address();

        test_exists(resource_addr);

        assert!(get_admin_address() == signer::address_of(admin), 222);
        assert!(is_wrapped_tokens_deployer_paused() == false, 222);
    }

    #[test(admin = @0xdeadbeef2)]
    fun test_set_wrapped_token_deployer_pause_state(
        admin: &signer
    ) {
        test_init_module(admin);

        assert!(is_wrapped_tokens_deployer_paused() == false, 222);
        set_wrapped_token_deployer_pause_state(admin, false);
        assert!(is_wrapped_tokens_deployer_paused() == false, 222);
    }

    #[test(admin = @0xdeadbeef2, minter = @0x222)]
    fun test_whitelist_and_remove_minter_for_token(
        admin: &signer, minter: &signer
    ) {
        test_init_module(admin);
        set_wrapped_token_deployer_pause_state(admin, false);
        assert!(!is_wrapped_tokens_deployer_paused(), 222);
        let minter_addr = signer::address_of(minter);
        let _chain_id = 1;
        let source_token_address =
            x"000000000000000000000000fff9976782d46cc05630d1f6ebab18b2324d6b14";
        let tokenIdentifier = generate_token_identifier_hash(1, source_token_address);

        create_wrapped_token(
            admin,
            0,
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            1,
            source_token_address
        );

        let wrapped_token_address = get_wrapped_token_address(tokenIdentifier);

        whitelist_minter_for_token(admin, minter_addr, wrapped_token_address);


        assert!(is_minter_whitelisted(wrapped_token_address, minter_addr), 222);

        remove_whitelisted_minter(admin, minter_addr, wrapped_token_address);
        assert!(!is_minter_whitelisted(wrapped_token_address, minter_addr), 222);
    }

    #[test(admin = @0xdeadbeef2, minter = @0x222)]
    fun test_claim_minter_capability_for_token(
        admin: &signer, minter: &signer
    ) {
        test_init_module(admin);
        set_wrapped_token_deployer_pause_state(admin, false);
        assert!(!is_wrapped_tokens_deployer_paused(), 222);
        let minter_addr = signer::address_of(minter);
        let _chain_id = 1;
        let source_token_address =
            x"000000000000000000000000fff9976782d46cc05630d1f6ebab18b2324d6b14";
        let tokenIdentifier = generate_token_identifier_hash(1, source_token_address);

        create_wrapped_token(
            admin,
            0,
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            1,
            source_token_address
        );

        let wrapped_token_address = get_wrapped_token_address(tokenIdentifier);

        whitelist_minter_for_token(admin, minter_addr, wrapped_token_address);

        assert!(is_minter_whitelisted(wrapped_token_address, minter_addr), 222);

        claim_minter_capability_for_token(minter, wrapped_token_address);
        test_ensure_mint_cap_exists(minter_addr);

        let minter_cap_addr = get_minter_capabilities(minter_addr);
        assert!(vector::length(&minter_cap_addr) == 1, 22);
        assert!(vector::pop_back(&mut minter_cap_addr) == wrapped_token_address, 22);

        remove_wrapped_token_from_minter_cap(admin, minter_addr, wrapped_token_address);

        let minter_cap_addr = get_minter_capabilities(minter_addr);
        assert!(vector::length(&minter_cap_addr) == 0, 22);
    }

    #[test(admin = @0xdeadbeef2, minter = @0x222)]
    fun test_remove_minter_capability(
        admin: &signer, minter: &signer
    ) {
        test_init_module(admin);
        set_wrapped_token_deployer_pause_state(admin, false);
        assert!(!is_wrapped_tokens_deployer_paused(), 222);
        let minter_addr = signer::address_of(minter);
        let _chain_id = 1;
        let source_token_address =
            x"000000000000000000000000fff9976782d46cc05630d1f6ebab18b2324d6b14";
        let tokenIdentifier = generate_token_identifier_hash(1, source_token_address);

        create_wrapped_token(
            admin,
            0,
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            1,
            source_token_address
        );

        let wrapped_token_address = get_wrapped_token_address(tokenIdentifier);

        whitelist_minter_for_token(admin, minter_addr, wrapped_token_address);


        assert!(is_minter_whitelisted(wrapped_token_address, minter_addr), 222);
        claim_minter_capability_for_token(minter, wrapped_token_address);
        test_ensure_mint_cap_exists(minter_addr);

        let minter_cap_addr = get_minter_capabilities(minter_addr);
        assert!(vector::length(&minter_cap_addr) == 1, 22);
        assert!(vector::pop_back(&mut minter_cap_addr) == wrapped_token_address, 22);
        remove_minter_capability(admin, minter_addr);
        assert!(!is_minter_whitelisted(wrapped_token_address, minter_addr), 222);
    }

    #[test(admin = @0xdeadbeef2)]
    fun test_resource_Account(admin: &signer) {
        let (resource_account, _g) = account::create_resource_account(admin, b"test");

        assert!(account::exists_at(address_of(&resource_account)), 22);
    }

    #[test(admin = @0xdeadbeef2, minter = @0x222)]
    fun test_create_wrapped_token(admin: &signer, minter: &signer) {
        test_init_module(admin);
        set_wrapped_token_deployer_pause_state(admin, false);
        assert!(!is_wrapped_tokens_deployer_paused(), 222);
        let _minter_addr = signer::address_of(minter);
        let _chain_id = 1;
        let source_token_address =
            x"000000000000000000000000fff9976782d46cc05630d1f6ebab18b2324d6b14";
        let tokenIdentifier = generate_token_identifier_hash(1, source_token_address);

        assert!(!is_token_registered(tokenIdentifier), 2222);

        create_wrapped_token(
            admin,
            0,
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            1,
            source_token_address
        );


        let _wrapped_token_address = get_wrapped_token_address(tokenIdentifier);
        assert!(is_token_registered(tokenIdentifier), 2222);
        assert!(is_token_active(tokenIdentifier), 2222);

        delist_wrapped_token(admin, tokenIdentifier);

        assert!(!is_token_active(tokenIdentifier), 2222);
    }

    #[test(admin = @0xdeadbeef2, minter = @0x222)]
    fun test_mint_wrapped_token(
        admin: &signer, minter: &signer
    ) {
        test_init_module(admin);
        set_wrapped_token_deployer_pause_state(admin, false);
        assert!(!is_wrapped_tokens_deployer_paused(), 222);
        let minter_addr = signer::address_of(minter);
        let _chain_id = 1;
        let source_token_address =
            x"000000000000000000000000fff9976782d46cc05630d1f6ebab18b2324d6b14";
        let tokenIdentifier = generate_token_identifier_hash(1, source_token_address);

        create_wrapped_token(
            admin,
            0,
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            string::utf8(b"WETH"),
            1,
            source_token_address
        );

        let wrapped_token_address = get_wrapped_token_address(tokenIdentifier);

        whitelist_minter_for_token(admin, minter_addr, wrapped_token_address);

        assert!(is_minter_whitelisted(wrapped_token_address, minter_addr), 222);

        claim_minter_capability_for_token(minter, wrapped_token_address);
        test_ensure_mint_cap_exists(minter_addr);

        let (minted_fa, token_metadata) =
            mint_wrapped_token(
                minter,
                wrapped_token_address,
                tokenIdentifier,
                10000
            );

        assert!(amount(&minted_fa) == 10000, 22);

        deposit(
            primary_fungible_store::ensure_primary_store_exists(
                minter_addr, token_metadata
            ),
            minted_fa
        );
    }
}
