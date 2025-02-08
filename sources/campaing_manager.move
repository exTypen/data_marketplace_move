module campaign_manager::CampaignManager {
    use std::signer;
    use std::table;
    use std::vector;
    use escrow_manager::EscrowManager;

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

    const ERR_INSUFFICIENT_FUNDS: u64 = 1;

    /// When the module is initialized, it runs automatically
    fun init_module(account: &signer) {
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
        // Get store from module address
        let module_addr = @campaign_manager;
        let store_ref = borrow_global_mut<CampaignStore>(module_addr);
        let id = store_ref.next_id;
        store_ref.next_id = id + 1;

        // First, lock the funds in the escrow
        EscrowManager::lock_funds(account, id, reward_pool, module_addr);

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
    public fun get_campaign(campaign_id: u64): Campaign acquires CampaignStore {
        let store_ref = borrow_global<CampaignStore>(@campaign_manager);
        *table::borrow(&store_ref.campaigns, campaign_id)
    }

    // Returns all campaigns in the store.
    #[view]
    public fun get_all_campaigns(): vector<Campaign> acquires CampaignStore {
        let store = borrow_global<CampaignStore>(@campaign_manager);
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
}
