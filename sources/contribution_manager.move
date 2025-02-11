module contribution_manager::ContributionManager {
    use std::signer;
    use std::vector;
    use std::table::{Self, Table};
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

    fun init_module(account: &signer) {
        let store = ContributionStore {
            contributions: table::new(),
        };
        move_to(account, store);
    }

    // Verify signature for contribution data
    fun verify_contribution_signature(
        campaign_id: u64,
        data_count: u64,
        store_cid: vector<u8>,
        score: u64,
        signature: vector<u8>
    ): bool {
        let message = vector::empty<u8>();
        vector::append(&mut message, bcs::to_bytes(&campaign_id));
        vector::append(&mut message, bcs::to_bytes(&data_count));
        
        // vector<u8> serialization - same format as TypeScript
        let store_cid_len = vector::length(&store_cid);
        vector::append(&mut message, bcs::to_bytes(&(store_cid_len as u64)));
        vector::append(&mut message, store_cid);
        
        vector::append(&mut message, bcs::to_bytes(&score));

        // Hash the message using SHA2-256
        let message_hash = hash::sha2_256(message);
        
        let public_key = x"2096c0773fc25243b95354d6dfd1bbcddd4516e29c260760bf504d041f645724";
        let unvalidated_public_key = ed25519::new_unvalidated_public_key_from_bytes(public_key);
        let signature = ed25519::new_signature_from_bytes(signature);
        ed25519::signature_verify_strict(&signature, &unvalidated_public_key, message_hash)
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
            verify_contribution_signature(campaign_id, data_count, store_cid, score, signature),
            0 // Signature verification failed
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
    fun test_add_contribution() acquires ContributionStore {
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
        let title = b"Test Campaign";
        let description = b"Test Description";
        let prompt = b"Test Prompt";
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
        
        // Prepare test data
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
    fun test_verified_contribution() acquires ContributionStore {
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
        let title = b"Test Campaign";
        let description = b"Test Description";
        let prompt = b"Test Prompt";
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
        
        // Prepare test data
        let data_count = 1;
        let store_cid = b"test";
        let score = 100;
        let signature = x"c163a47a4a843d7ae8f2e5c72143a2098ff49fe8acb98a4392eba189c8acbe3be8c21b090c2d39dab78c01cfdd58204764223c50c5f48efe6fbb6d1d4d426706";
        
        // Add contribution
        add_contribution(&test_account, campaign_id, data_count, store_cid, score, signature);
        
        // Check contributions
        let contributions = get_campaign_contributions(campaign_id);
        assert!(vector::length(&contributions) == 1, 1);

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
    fun test_multiple_contributions() acquires ContributionStore {
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
        let title = b"Test Campaign";
        let description = b"Test Description";
        let prompt = b"Test Prompt";
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
        
        // Prepare test data
        let store_cid = b"test";
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

