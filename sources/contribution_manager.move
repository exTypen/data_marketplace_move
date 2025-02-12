module contribution_manager::ContributionManager {
    use std::signer;
    use std::vector;
    use std::table::{Self, Table};
    use std::string::{Self, String};

    use aptos_framework::bcs;
    use aptos_std::ed25519;
    use aptos_std::hash;
    use campaign_manager::CampaignManager;
    use escrow_manager::EscrowManager;
    #[test_only]
    use aptos_framework::account;
    #[test_only]
    use aptos_framework::aptos_coin;
    #[test_only]
    use aptos_framework::coin;

    // Sturctre of Contribution
    struct Contribution has store, drop, copy {
        campaign_id: u64,
        contributor: address,
        data_count: u64,
        store_cid: String,
        score: u64,
        signature: vector<u8>,
    }

    // Store for Contribution
    struct ContributionStore has key {
        contributions: Table<u64, vector<Contribution>>, // campaign_id -> contributions
    }

    // Trusted public keys store
    struct TrustedPublicKeys has key {
        creator: address,
        keys: vector<vector<u8>>,
    }

    // Error codes
    const ERR_CAMPAIGN_NOT_FOUND: u64 = 1;
    const ERR_INVALID_DATA_COUNT: u64 = 2;
    const ERR_NOT_CREATOR: u64 = 3;
    const ERR_KEY_ALREADY_EXISTS: u64 = 4;
    const ERR_KEY_NOT_FOUND: u64 = 5;
    const ERR_NO_VALID_SIGNATURE: u64 = 6;

    fun init_module(account: &signer) {
        let store = ContributionStore {
            contributions: table::new(),
        };
        move_to(account, store);

        // Initialize trusted public keys with empty vector
        let trusted_keys = TrustedPublicKeys {
            creator: signer::address_of(account),
            keys: vector::empty<vector<u8>>(),
        };
        move_to(account, trusted_keys);
    }

    // Add a new trusted public key
    public entry fun add_trusted_key(account: &signer, public_key: vector<u8>) acquires TrustedPublicKeys {
        let trusted_keys = borrow_global_mut<TrustedPublicKeys>(@contribution_manager);
        assert!(signer::address_of(account) == trusted_keys.creator, ERR_NOT_CREATOR);
        
        // Check if key already exists
        let i = 0;
        let len = vector::length(&trusted_keys.keys);
        while (i < len) {
            assert!(*vector::borrow(&trusted_keys.keys, i) != public_key, ERR_KEY_ALREADY_EXISTS);
            i = i + 1;
        };
        
        vector::push_back(&mut trusted_keys.keys, public_key);
    }

    // Remove a trusted public key
    public entry fun remove_trusted_key(account: &signer, public_key: vector<u8>) acquires TrustedPublicKeys {
        let trusted_keys = borrow_global_mut<TrustedPublicKeys>(@contribution_manager);
        assert!(signer::address_of(account) == trusted_keys.creator, ERR_NOT_CREATOR);
        
        let i = 0;
        let len = vector::length(&trusted_keys.keys);
        let found = false;
        
        while (i < len) {
            if (*vector::borrow(&trusted_keys.keys, i) == public_key) {
                vector::remove(&mut trusted_keys.keys, i);
                found = true;
                break
            };
            i = i + 1;
        };
        
        assert!(found, ERR_KEY_NOT_FOUND);
    }

    // Get all trusted public keys
    #[view]
    public fun get_trusted_keys(): vector<vector<u8>> acquires TrustedPublicKeys {
        let trusted_keys = borrow_global<TrustedPublicKeys>(@contribution_manager);
        trusted_keys.keys
    }

    // Verify signature for contribution data
    fun verify_contribution_signature(
        campaign_id: u64,
        data_count: u64,
        store_cid: String,
        score: u64,
        signature: vector<u8>
    ): bool acquires TrustedPublicKeys {
        let message = vector::empty<u8>();
        vector::append(&mut message, bcs::to_bytes(&campaign_id));
        vector::append(&mut message, bcs::to_bytes(&data_count));
        
        let store_cid_bytes = string::bytes(&store_cid);
        vector::append(&mut message, bcs::to_bytes(&(store_cid_bytes.length() as u64)));
        vector::append(&mut message, *store_cid_bytes);
        
        vector::append(&mut message, bcs::to_bytes(&score));

        let message_hash = hash::sha2_256(message);
        let signature = ed25519::new_signature_from_bytes(signature);
        
        let trusted_keys = borrow_global<TrustedPublicKeys>(@contribution_manager);
        let i = 0;
        let len = vector::length(&trusted_keys.keys);
        
        while (i < len) {
            let public_key = vector::borrow(&trusted_keys.keys, i);
            let unvalidated_public_key = ed25519::new_unvalidated_public_key_from_bytes(*public_key);
            if (ed25519::signature_verify_strict(&signature, &unvalidated_public_key, message_hash)) {
                return true
            };
            i = i + 1;
        };
        
        false
    }

    // Add a new contribution
    public entry fun add_contribution(
        account: &signer,
        campaign_id: u64,
        data_count: u64,
        store_cid: String,
        score: u64,
        signature: vector<u8>,
    ) acquires ContributionStore, TrustedPublicKeys {
        // Verify the signature
        assert!(
            verify_contribution_signature(campaign_id, data_count, store_cid, score, signature),
            ERR_NO_VALID_SIGNATURE
        );

        let contribution = Contribution {
            campaign_id,
            contributor: signer::address_of(account),
            data_count,
            store_cid,
            score,
            signature
        };

        let store = borrow_global_mut<ContributionStore>(@contribution_manager);
        
        if (!table::contains(&store.contributions, campaign_id)) {
            table::add(&mut store.contributions, campaign_id, vector::empty<Contribution>());
        };
        
        let contributions = table::borrow_mut(&mut store.contributions, campaign_id);
        vector::push_back(contributions, contribution);

        let unit_price = CampaignManager::get_unit_price(campaign_id);
        let total_reward = data_count * unit_price;
        
        EscrowManager::release_funds_for_data(
            campaign_id,
            signer::address_of(account),
            total_reward
        );
    }

    // Get all contributions
    #[view]
    public fun get_all_contributions(): vector<Contribution> acquires ContributionStore {
        let store = borrow_global<ContributionStore>(@contribution_manager);
        let result = vector::empty<Contribution>();
        let campaign_ids = CampaignManager::get_all_campaign_ids();
        let i = 0;
        while (i < vector::length(&campaign_ids)) {
            let campaign_id = *vector::borrow(&campaign_ids, i);
            if (table::contains(&store.contributions, campaign_id)) {
                let campaign_contributions = table::borrow(&store.contributions, campaign_id);
                let j = 0;
                while (j < vector::length(campaign_contributions)) {
                    let contribution = vector::borrow(campaign_contributions, j);
                    vector::push_back(&mut result, *contribution);
                    j = j + 1;
                };
            };
            i = i + 1;
        };
        result
    }

    // Get all contributions for a campaign
    #[view]
    public fun get_campaign_contributions(campaign_id: u64): vector<Contribution> acquires ContributionStore {
        let store = borrow_global<ContributionStore>(@contribution_manager);
        if (!table::contains(&store.contributions, campaign_id)) {
            return vector::empty<Contribution>();
        };
        *table::borrow(&store.contributions, campaign_id)
    }

    // Get all contributions for a contributor
    #[view]
    public fun get_contributor_contributions(contributor: address): vector<Contribution> acquires ContributionStore {
        let store = borrow_global<ContributionStore>(@contribution_manager);
        let result = vector::empty<Contribution>();
        let campaign_ids = CampaignManager::get_all_campaign_ids();
        let i = 0;
        while (i < vector::length(&campaign_ids)) {
            let campaign_id = *vector::borrow(&campaign_ids, i);
            if (table::contains(&store.contributions, campaign_id)) {
                let campaign_contributions = table::borrow(&store.contributions, campaign_id);
                let j = 0;
                while (j < vector::length(campaign_contributions)) {
                    let contribution = vector::borrow(campaign_contributions, j);
                    if (contribution.contributor == contributor) {
                        vector::push_back(&mut result, *contribution);
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };
        result
    }

    #[test]
    #[expected_failure(abort_code = 65538)] // ED25519 signature size error
    fun test_add_contribution() acquires ContributionStore, TrustedPublicKeys {
        // Create test accounts
        let test_account = account::create_account_for_test(@0x1);
        let campaign_manager_account = account::create_account_for_test(@campaign_manager);
        let contribution_manager = account::create_account_for_test(@contribution_manager);
        let escrow_manager = account::create_account_for_test(@escrow_manager);
        
        // Initialize AptosCoin
        let framework_signer = account::create_account_for_test(@0x1);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework_signer);

        // Register coin stores
        coin::register<aptos_coin::AptosCoin>(&test_account);
        coin::register<aptos_coin::AptosCoin>(&campaign_manager_account);
        let coins = coin::mint<aptos_coin::AptosCoin>(10000, &mint_cap);
        coin::deposit(signer::address_of(&campaign_manager_account), coins);
        
        // Initialize modules
        init_module(&contribution_manager);
        CampaignManager::initialize_for_test(&campaign_manager_account);
        EscrowManager::initialize_for_test(&escrow_manager);

        // Create test campaign
        let campaign_id = 1;
        let unit_price = 100;
        let title = string::utf8(b"Test Campaign");
        let description = string::utf8(b"Test Description");
        let prompt = string::utf8(b"Test Prompt");
        let minimum_contribution = 0;
        let reward_pool = 1000;
        
        CampaignManager::create_campaign(
            &campaign_manager_account,
            title,
            description,
            prompt,
            unit_price,
            minimum_contribution,
            reward_pool
        );
        
        // Add test public key
        let test_public_key =  b"test_public_key_1" ;
        add_trusted_key(&contribution_manager, test_public_key);
        
        // Prepare test data with invalid signature (expected to fail)
        let data_count = 1;
        let store_cid = string::utf8(b"test");
        let score = 100;
        let signature =  b"test_signature" ;
        
        // This should fail because signature is not a valid ED25519 signature
        add_contribution(&test_account, campaign_id, data_count, store_cid, score, signature);
        
        // Clean up
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test]
    #[expected_failure(abort_code = 65538)] // ED25519 signature size error
    fun test_verified_contribution() acquires ContributionStore, TrustedPublicKeys {
        // Create test accounts
        let test_account = account::create_account_for_test(@0x1);
        let campaign_manager = account::create_account_for_test(@campaign_manager);
        let contribution_manager = account::create_account_for_test(@contribution_manager);
        let escrow_manager = account::create_account_for_test(@escrow_manager);
        
        // Initialize AptosCoin
        let framework_signer = account::create_account_for_test(@0x1);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework_signer);

        // Create coin records for test accounts and add balance
        coin::register<aptos_coin::AptosCoin>(&test_account);
        coin::register<aptos_coin::AptosCoin>(&campaign_manager);
        let coins = coin::mint<aptos_coin::AptosCoin>(10000, &mint_cap);
        coin::deposit(signer::address_of(&campaign_manager), coins);
        
        // Initialize modules
        init_module(&contribution_manager);
        CampaignManager::initialize_for_test(&campaign_manager);
        EscrowManager::initialize_for_test(&escrow_manager);
        
        // Create test campaign
        let campaign_id = 1;
        let unit_price = 100;
        let title = string::utf8(b"Test Campaign");
        let description = string::utf8(b"Test Description");
        let prompt = string::utf8(b"Test Prompt");
        let minimum_contribution = 0;
        let reward_pool = 1000;
        
        CampaignManager::create_campaign(
            &campaign_manager,
            title,
            description,
            prompt,
            unit_price,
            minimum_contribution,
            reward_pool
        );
        
        // Add test public key
        let test_public_key = b"test_public_key_1";
        add_trusted_key(&contribution_manager, test_public_key);
        
        // Prepare test data with invalid signature (expected to fail)
        let data_count = 1;
        let store_cid = string::utf8(b"test");
        let score = 100;
        let signature =   b"test_signature" ;
        
        // This should fail because signature is not a valid ED25519 signature
        add_contribution(&test_account, campaign_id, data_count, store_cid, score, signature);
        
        // Clean up capabilities
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test]
    fun test_get_empty_campaign_contributions() acquires ContributionStore {
        // Test hesabini olustur
        let contribution_manager = account::create_account_for_test(@contribution_manager);
        
        // Modulu baslat
        init_module(&contribution_manager);
        
        // Var olmayan kampanya icin katkilari al
        let contributions = get_campaign_contributions(999);
        assert!(vector::length(&contributions) == 0, 1);
    }

    #[test]
    #[expected_failure(abort_code = 65538)] // ED25519 signature size error
    fun test_multiple_contributions() acquires ContributionStore, TrustedPublicKeys {
        // Create test accounts
        let test_account1 = account::create_account_for_test(@0x1);
        let test_account2 = account::create_account_for_test(@0x2);
        let campaign_manager_account = account::create_account_for_test(@campaign_manager);
        let contribution_manager = account::create_account_for_test(@contribution_manager);
        let escrow_manager = account::create_account_for_test(@escrow_manager);
        
        // Initialize AptosCoin
        let framework_signer = account::create_account_for_test(@0x1);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework_signer);

        // Register coin stores
        coin::register<aptos_coin::AptosCoin>(&test_account1);
        coin::register<aptos_coin::AptosCoin>(&test_account2);
        coin::register<aptos_coin::AptosCoin>(&campaign_manager_account);
        let coins = coin::mint<aptos_coin::AptosCoin>(10000, &mint_cap);
        coin::deposit(signer::address_of(&campaign_manager_account), coins);
        
        // Initialize modules
        init_module(&contribution_manager);
        CampaignManager::initialize_for_test(&campaign_manager_account);
        EscrowManager::initialize_for_test(&escrow_manager);

        // Create test campaign
        let campaign_id = 1;
        let unit_price = 100;
        let title = string::utf8(b"Test Campaign");
        let description = string::utf8(b"Test Description");
        let prompt = string::utf8(b"Test Prompt");
        let minimum_contribution = 0;
        let reward_pool = 1000;
        
        CampaignManager::create_campaign(
            &campaign_manager_account,
            title,
            description,
            prompt,
            unit_price,
            minimum_contribution,
            reward_pool
        );
        
        // Add test public key
        let test_public_key = b"test_public_key_1";
        add_trusted_key(&contribution_manager, test_public_key);
        
        // Prepare test data with invalid signature (expected to fail)
        let data_count = 1;
        let store_cid = string::utf8(b"test");
        let score = 100;
        let signature =  b"test_signature"  ;
        
        // These should fail because signature is not a valid ED25519 signature
        add_contribution(&test_account1, campaign_id, data_count, store_cid, score, signature);
        add_contribution(&test_account2, campaign_id, data_count, store_cid, score, signature);
        
        // Clean up
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }
}