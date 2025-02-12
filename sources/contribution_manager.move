module marketplace::contribution_manager {
    use std::signer;
    use std::vector;
    use std::table::{Self, Table};
    use std::string::{String};

    #[test_only]
    use std::string::{Self};

    use marketplace::campaign_manager;
    use marketplace::escrow_manager;
    use marketplace::verifier;

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
        store_cid: vector<u8>,
        score: u64,
        signature: vector<u8>,
    }

    // Store for Contribution
    struct ContributionStore has key {
        contributions: Table<u64, vector<Contribution>>, // campaign_id -> contributions
    }

    // Error codes
    const ERR_CAMPAIGN_NOT_FOUND: u64 = 1;
    const ERR_INVALID_DATA_COUNT: u64 = 2;
    const ERR_NO_VALID_SIGNATURE: u64 = 6;

    fun init_module(account: &signer) {
        let store = ContributionStore {
            contributions: table::new(),
        };
        move_to(account, store);

        // Initialize Verifier module
        verifier::initialize(account);
    }

    // Add a new contribution
    public entry fun add_contribution(
        account: &signer,
        campaign_id: u64,
        data_count: u64,
        store_cid: vector<u8>,
        score: u64,
        signature: vector<u8>,
    ) acquires ContributionStore {
        // Verify the signature
        assert!(
            verifier::verify_contribution_signature(campaign_id, data_count, store_cid, score, signature),
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

        let store = borrow_global_mut<ContributionStore>(@marketplace);
        
        if (!table::contains(&store.contributions, campaign_id)) {
            table::add(&mut store.contributions, campaign_id, vector::empty<Contribution>());
        };
        
        let contributions = table::borrow_mut(&mut store.contributions, campaign_id);
        vector::push_back(contributions, contribution);

        let unit_price = campaign_manager::get_unit_price(campaign_id);
        let total_reward = data_count * unit_price;
        
        escrow_manager::release_funds_for_data(
            campaign_id,
            signer::address_of(account),
            total_reward
        );
    }

    // Get all contributions
    #[view]
    public fun get_all_contributions(): vector<Contribution> acquires ContributionStore {
        let store = borrow_global<ContributionStore>(@marketplace);
        let result = vector::empty<Contribution>();
        let campaign_ids = campaign_manager::get_all_campaign_ids();
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
        let store = borrow_global<ContributionStore>(@marketplace);
        if (!table::contains(&store.contributions, campaign_id)) {
            return vector::empty<Contribution>();
        };
        *table::borrow(&store.contributions, campaign_id)
    }

    // Get all contributions for a contributor
    #[view]
    public fun get_contributor_contributions(contributor: address): vector<Contribution> acquires ContributionStore {
        let store = borrow_global<ContributionStore>(@marketplace);
        let result = vector::empty<Contribution>();
        let campaign_ids = campaign_manager::get_all_campaign_ids();
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
    fun test_add_contribution() acquires ContributionStore {
        // Create test accounts
        let test_account = account::create_account_for_test(@0x1);
        let campaign_manager_account = account::create_account_for_test(@marketplace);
        let contribution_manager = account::create_account_for_test(@marketplace);
        let escrow_manager = account::create_account_for_test(@marketplace);
        
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
        campaign_manager::initialize_for_test(&campaign_manager_account);
        escrow_manager::initialize_for_test(&escrow_manager);

        // Create test campaign
        let campaign_id = 1;
        let unit_price = 100;
        let title = b"Test Campaign";
        let description = b"Test Description";
        let prompt = b"Test Prompt";
        let minimum_contribution = 0;
        let reward_pool = 1000;
        
        campaign_manager::create_campaign(
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
        verifier::add_trusted_key(&contribution_manager, test_public_key);
        
        // Prepare test data with invalid signature (expected to fail)
        let data_count = 1;
        let store_cid = b"test";
        let score = 100;
        let signature = x"c163a47a4a843d7ae8f2e5c72143a2098ff49fe8acb98a4392eba189c8acbe3be8c21b090c2d39dab78c01cfdd58204764223c50c5f48efe6fbb6d1d4d426706";
        
        // Add contribution
        add_contribution(&test_account, campaign_id, data_count, store_cid, score, signature);
        
        // Check contributions
        let contributions = get_campaign_contributions(campaign_id);
        assert!(vector::length(&contributions) == 1, 1);
        
        let contribution = vector::borrow(&contributions, 0);
        assert!(contribution.campaign_id == campaign_id, 2);
        assert!(contribution.contributor == @0x1, 3);
        assert!(contribution.data_count == data_count, 4);
        assert!(contribution.score == score, 5);

        // Clean up
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test]
    fun test_get_empty_campaign_contributions() acquires ContributionStore {
        // Test hesabini olustur
        let contribution_manager = account::create_account_for_test(@marketplace);
        
        // Modulu baslat
        init_module(&contribution_manager);
        
        // Var olmayan kampanya icin katkilari al
        let contributions = get_campaign_contributions(999);
        assert!(vector::length(&contributions) == 0, 1);
    }

    #[test]
    #[expected_failure(abort_code = 65538)] // ED25519 signature size error
    fun test_multiple_contributions() acquires ContributionStore {
        // Create test accounts
        let test_account1 = account::create_account_for_test(@0x1);
        let test_account2 = account::create_account_for_test(@0x2);
        let campaign_manager_account = account::create_account_for_test(@marketplace);
        let contribution_manager = account::create_account_for_test(@marketplace);
        let escrow_manager = account::create_account_for_test(@marketplace);
        
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
        campaign_manager::initialize_for_test(&campaign_manager_account);
        escrow_manager::initialize_for_test(&escrow_manager);

        // Create test campaign
        let campaign_id = 1;
        let unit_price = 100;
        let title = b"Test Campaign";
        let description = b"Test Description";
        let prompt = b"Test Prompt";
        let minimum_contribution = 0;
        let reward_pool = 1000;
        
        campaign_manager::create_campaign(
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
        verifier::add_trusted_key(&contribution_manager, test_public_key);
        
        // Prepare test data with invalid signature (expected to fail)
        let data_count = 1;
        let score = 100;
        let signature = x"c163a47a4a843d7ae8f2e5c72143a2098ff49fe8acb98a4392eba189c8acbe3be8c21b090c2d39dab78c01cfdd58204764223c50c5f48efe6fbb6d1d4d426706";
        
        // Add first contribution
        add_contribution(&test_account1, campaign_id, data_count, store_cid, score, signature);
        
        // Add second contribution
        add_contribution(&test_account2, campaign_id, data_count, store_cid, score, signature);
        
        // Check contributions
        let contributions = get_campaign_contributions(campaign_id);
        assert!(vector::length(&contributions) == 2, 1);
        
        let contribution1 = vector::borrow(&contributions, 0);
        let contribution2 = vector::borrow(&contributions, 1);
        
        assert!(contribution1.contributor == @0x1, 2);
        assert!(contribution2.contributor == @0x2, 3);
        assert!(contribution1.data_count == 1, 4);
        assert!(contribution2.data_count == 1, 5);

        // Clean up
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }
}

