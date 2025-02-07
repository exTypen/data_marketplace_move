module campaign_manager_v2::CampaignManagerV2 {
    use std::signer;
    use std::table;
    use std::vector;
    #[test_only]
    use aptos_framework::account;

    // Campaign structure.
    struct Campaign has store, drop, copy {
        id: u64,
        creator: address,
        data_spec: vector<u8>,
        quality_criteria: vector<u8>,
        reward_pool: u64,
        active: bool,
    }
    
    // Store using table to store campaigns.
    struct CampaignStore has key {
        campaigns: table::Table<u64, Campaign>,
        next_id: u64,
    }

    // Initializes the CampaignStore.
    public entry fun init_campaign_store(account: &signer) {
        let store = CampaignStore {
            campaigns: table::new<u64, Campaign>(),
            next_id: 1,
        };
        move_to(account, store);
    }

    // Creates a new campaign and adds it to the store.
    public entry fun create_campaign(
        account: &signer,
        data_spec: vector<u8>,
        quality_criteria: vector<u8>,
        reward_pool: u64
    ) acquires CampaignStore {
        let store_ref = borrow_global_mut<CampaignStore>(signer::address_of(account));
        let id = store_ref.next_id;
        store_ref.next_id = id + 1;
        let new_campaign = Campaign {
            id,
            creator: signer::address_of(account),
            data_spec,
            quality_criteria,
            reward_pool,
            active: true,
        };
        table::add(&mut store_ref.campaigns, id, new_campaign);
    }

    // Returns the campaign with the specified ID.
    #[view]
    public fun get_campaign(campaign_id: u64, store_addr: address): Campaign acquires CampaignStore {
        let store_ref = borrow_global<CampaignStore>(store_addr);
        *table::borrow(&store_ref.campaigns, campaign_id)
    }

    // Returns all campaigns in the store.
    #[view]
    public fun get_all_campaigns(store_addr: address): vector<Campaign> acquires CampaignStore {
        let store = borrow_global<CampaignStore>(store_addr);
        let campaigns = vector::empty<Campaign>();
        let i = 1;
        while (i < store.next_id) {
            if (table::contains(&store.campaigns, i)) {
                let camp = *table::borrow(&store.campaigns, i);
                vector::push_back(&mut campaigns, camp);
            };
            i = i + 1;
        };
        campaigns
    }

    // ============ Tests ============

    #[test_only]
    fun create_test_account(): signer {
        account::create_account_for_test(@0x1)
    }

    #[test]
    fun test_init_campaign_store() {
        let account = create_test_account();
        init_campaign_store(&account);
    }

    #[test]
    fun test_create_and_get_campaign() acquires CampaignStore {
        let account = create_test_account();
        let account_addr = signer::address_of(&account);
        
        // Initialize CampaignStore
        init_campaign_store(&account);
        
        // Prepare test data
        let data_spec = b"test_data_spec";
        let quality_criteria = b"test_quality_criteria";
        let reward_pool = 1000;
        
        // Create new campaign
        create_campaign(
            &account,
            data_spec,
            quality_criteria,
            reward_pool
        );
        
        // Get campaign by ID and verify
        let campaign = get_campaign(1, account_addr);
        assert!(campaign.id == 1, 0);
        assert!(campaign.creator == account_addr, 1);
        assert!(campaign.reward_pool == reward_pool, 2);
        assert!(campaign.active == true, 3);
    }
    
    #[test]
    fun test_get_all_campaigns() acquires CampaignStore {
        let account = create_test_account();
        let account_addr = signer::address_of(&account);
        
        // Initialize CampaignStore
        init_campaign_store(&account);
        
        // Create multiple campaigns
        create_campaign(&account, b"data1", b"criteria1", 1000);
        create_campaign(&account, b"data2", b"criteria2", 2000);
        
        // Get all campaigns
        let campaigns = get_all_campaigns(account_addr);
        assert!(vector::length(&campaigns) == 2, 0);
        let first_campaign = vector::borrow(&campaigns, 0);
        assert!(first_campaign.reward_pool == 1000, 1);
    }
}
