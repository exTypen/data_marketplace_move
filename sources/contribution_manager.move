module contribution_manager::ContributionManager {
    use std::signer;
    use std::vector;
    use std::table::{Self, Table};
    use std::string::{Self, String};
    use campaign_manager::CampaignManager;
    use escrow_manager::EscrowManager;

    // Sturctre of Contribution
    struct Contribution has store, drop, copy {
        campaign_id: u64,
        contributor: address,
        data_count: u64,
        data: String,
        verified: bool,
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

    // Add a new contribution
    public entry fun add_contribution(
        account: &signer,
        campaign_id: u64,
        data_count: u64,
        data: String,
        verified: bool
    ) acquires ContributionStore {
        // Check the existence of the campaign and its details
        let contribution = Contribution {
            campaign_id,
            contributor: signer::address_of(account),
            data_count,
            data,
            verified,
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
}

