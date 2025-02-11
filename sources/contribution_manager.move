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
        store_key: vector<u8>,
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
        store_key: vector<u8>,
        score: u64,
        signature: vector<u8>
    ): bool {
        let message = vector::empty<u8>();
        vector::append(&mut message, bcs::to_bytes(&campaign_id));
        vector::append(&mut message, bcs::to_bytes(&data_count));
        
        // vector<u8> serialization - same format as TypeScript
        let store_key_len = vector::length(&store_key);
        vector::append(&mut message, bcs::to_bytes(&(store_key_len as u64)));
        vector::append(&mut message, store_key);
        
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
        store_key: vector<u8>,
        score: u64,
        signature: vector<u8>,
    ) acquires ContributionStore {
        // Check the existence of the campaign and its details
        let contribution = Contribution {
            campaign_id,
            contributor: signer::address_of(account),
            data_count,
            store_key,
            score,
            signature
        };

        // Get the store
        let store = borrow_global_mut<ContributionStore>(@contribution_manager);
        
        // If the contribution list for the campaign does not exist, create it
        if (!table::contains(&store.contributions, campaign_id)) {
            table::add(&mut store.contributions, campaign_id, vector::empty<Contribution>());
        };
        
        // Add the contribution to the list
        let contributions = table::borrow_mut(&mut store.contributions, campaign_id);
        vector::push_back(contributions, contribution);

        let verified = verify_contribution_signature(campaign_id, data_count, store_key, score, signature);

        // If verified is true, release the funds
        if (verified) {
            let unit_price = CampaignManager::get_unit_price(campaign_id);
            let total_reward = data_count * unit_price;
            
            // Release the funds from the escrow for data contribution
            EscrowManager::release_funds_for_data(
                campaign_id,
                signer::address_of(account),
                @campaign_manager,
                total_reward
            );
        };
    }

    // Get all contributions for a campaign
    #[view]
    public fun get_campaign_contributions(campaign_id: u64): vector<Contribution> acquires ContributionStore {
        let store = borrow_global<ContributionStore>(@contribution_manager);
        if (!table::contains(&store.contributions, campaign_id)) {
            return vector::empty<Contribution>()
        };
        *table::borrow(&store.contributions, campaign_id)
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
        let data_spec = b"Test Data Spec";
        let reward_pool = 1000;
        
        CampaignManager::create_campaign(
            &campaign_manager_account,
            title,
            description,
            data_spec,
            unit_price,
            reward_pool
        );
        
        // Prepare test data
        let data_count = 1;
        let store_key = b"test_store_key";
        let score = 100;
        let signature = x"385b82c2c661ee95ee7e012dccaf3aee4c35182550d1969f09aba17b22dd8a3375d5923d1a92e20d424b4062ac19e4ea68bab8a966905604d1bfc4d3b47c780c";
        
        // Add contribution
        add_contribution(&test_account, campaign_id, data_count, store_key, score, signature);
        
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
        let data_spec = b"Test Data Spec";
        let reward_pool = 1000;
        
        CampaignManager::create_campaign(
            &campaign_manager,
            title,
            description,
            data_spec,
            unit_price,
            reward_pool
        );
        
        // Prepare test data
        let data_count = 1;
        let store_key = b"test_store_key";
        let score = 100;
        let signature = x"385b82c2c661ee95ee7e012dccaf3aee4c35182550d1969f09aba17b22dd8a3375d5923d1a92e20d424b4062ac19e4ea68bab8a966905604d1bfc4d3b47c780c"; // Example signature for test
        
        // Add contribution
        add_contribution(&test_account, campaign_id, data_count, store_key, score, signature);
        
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
        let data_spec = b"Test Data Spec";
        let reward_pool = 1000;
        
        CampaignManager::create_campaign(
            &campaign_manager_account,
            title,
            description,
            data_spec,
            unit_price,
            reward_pool
        );
        
        // Prepare test data
        let store_key = b"test_store_key";
        let score = 100;
        let signature = x"385b82c2c661ee95ee7e012dccaf3aee4c35182550d1969f09aba17b22dd8a3375d5923d1a92e20d424b4062ac19e4ea68bab8a966905604d1bfc4d3b47c780c";
        
        // Add first contribution
        add_contribution(&test_account1, campaign_id, 5, store_key, score, signature);
        
        // Add second contribution
        add_contribution(&test_account2, campaign_id, 3, store_key, score, signature);
        
        // Check contributions
        let contributions = get_campaign_contributions(campaign_id);
        assert!(vector::length(&contributions) == 2, 1);
        
        let contribution1 = vector::borrow(&contributions, 0);
        let contribution2 = vector::borrow(&contributions, 1);
        
        assert!(contribution1.contributor == @0x1, 2);
        assert!(contribution2.contributor == @0x2, 3);
        assert!(contribution1.data_count == 5, 4);
        assert!(contribution2.data_count == 3, 5);

        // Clean up
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }
}

