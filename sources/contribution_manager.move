module contribution_manager::ContributionManager {
    use std::signer;
    use std::vector;
    use std::table::{Self, Table};
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
        data: vector<u8>,
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
        data: vector<u8>,
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

    #[test]
    fun test_add_contribution() acquires ContributionStore {
        // Test hesabini olustur
        let test_account = account::create_account_for_test(@0x1);
        let _campaign_manager = account::create_account_for_test(@campaign_manager);
        let contribution_manager = account::create_account_for_test(@contribution_manager);
        
        // Modulu baslat
        init_module(&contribution_manager);
        
        // Test verilerini hazirla
        let campaign_id = 1;
        let data_count = 5;
        let data = vector::empty<u8>();
        vector::push_back(&mut data, 1);
        let verified = false;
        
        // Katki ekle
        add_contribution(&test_account, campaign_id, data_count, data, verified);
        
        // Katkilari kontrol et
        let contributions = get_campaign_contributions(campaign_id);
        assert!(vector::length(&contributions) == 1, 1);
        
        let contribution = vector::borrow(&contributions, 0);
        assert!(contribution.campaign_id == campaign_id, 2);
        assert!(contribution.contributor == @0x1, 3);
        assert!(contribution.data_count == data_count, 4);
        assert!(contribution.verified == verified, 5);
    }

    #[test]
    fun test_verified_contribution() acquires ContributionStore {
        // Test hesaplarini olustur
        let test_account = account::create_account_for_test(@0x1);
        let campaign_manager = account::create_account_for_test(@campaign_manager);
        let contribution_manager = account::create_account_for_test(@contribution_manager);
        let escrow_manager = account::create_account_for_test(@escrow_manager);
        
        // AptosCoin'i baslat
        let framework_signer = account::create_account_for_test(@0x1);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework_signer);

        // Test hesaplari icin coin kaydi olustur ve bakiye ekle
        coin::register<aptos_coin::AptosCoin>(&test_account);
        coin::register<aptos_coin::AptosCoin>(&campaign_manager);
        let coins = coin::mint<aptos_coin::AptosCoin>(10000, &mint_cap);
        coin::deposit(signer::address_of(&campaign_manager), coins);
        
        // Modulleri baslat
        init_module(&contribution_manager);
        CampaignManager::initialize_for_test(&campaign_manager);
        EscrowManager::initialize_for_test(&escrow_manager);
        
        // Test kampanyasi olustur
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
        
        // Test verilerini hazirla
        let data_count = 5;
        let data = vector::empty<u8>();
        vector::push_back(&mut data, 1);
        let verified = true;
        
        // Dogrulanmis katki ekle
        add_contribution(&test_account, campaign_id, data_count, data, verified);
        
        // Katkilari kontrol et
        let contributions = get_campaign_contributions(campaign_id);
        assert!(vector::length(&contributions) == 1, 1);
        
        let contribution = vector::borrow(&contributions, 0);
        assert!(contribution.verified == true, 2);

        // Yetenekleri temizle
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
        // Test hesaplarini olustur
        let test_account1 = account::create_account_for_test(@0x1);
        let test_account2 = account::create_account_for_test(@0x2);
        let contribution_manager = account::create_account_for_test(@contribution_manager);
        
        // Modulu baslat
        init_module(&contribution_manager);
        
        // Test verilerini hazirla
        let campaign_id = 1;
        let data = vector::empty<u8>();
        vector::push_back(&mut data, 1);
        
        // Ilk katkiyi ekle
        add_contribution(&test_account1, campaign_id, 5, data, false);
        
        // Ikinci katkiyi ekle
        add_contribution(&test_account2, campaign_id, 3, data, false);
        
        // Katkilari kontrol et
        let contributions = get_campaign_contributions(campaign_id);
        assert!(vector::length(&contributions) == 2, 1);
        
        let contribution1 = vector::borrow(&contributions, 0);
        let contribution2 = vector::borrow(&contributions, 1);
        
        assert!(contribution1.contributor == @0x1, 2);
        assert!(contribution2.contributor == @0x2, 3);
        assert!(contribution1.data_count == 5, 4);
        assert!(contribution2.data_count == 3, 5);
    }
}

