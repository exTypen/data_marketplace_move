module campaign_manager::CampaignManager {
    use std::signer;
    use std::table;
    use std::vector;
    use escrow_manager::EscrowManager;

    // Campaign structure.
    struct Campaign has store, drop, copy {
        id: u64,
        creator: address,
        title: vector<u8>,
        description: vector<u8>,
        data_spec: vector<u8>,
        reward_pool: u64,
        remaining_reward: u64,
        unit_price: u64,
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
        title: vector<u8>,
        description: vector<u8>,
        data_spec: vector<u8>,
        unit_price: u64,
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
            title,
            description,
            data_spec,
            unit_price,
            reward_pool,
            remaining_reward: reward_pool,
            active: true,
        };
        table::add(&mut store_ref.campaigns, id, new_campaign);
    }

    // Returns the campaign with the specified ID.
    #[view]
    public fun get_campaign(campaign_id: u64): Campaign acquires CampaignStore {
        let store_ref = borrow_global<CampaignStore>(@campaign_manager);
        let campaign = *table::borrow(&store_ref.campaigns, campaign_id);
        
        // Get the remaining amount in the escrow
        campaign.remaining_reward = EscrowManager::get_locked_amount(campaign_id, @campaign_manager);
        campaign
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
                // For each campaign, get the remaining amount in the escrow
                camp.remaining_reward = EscrowManager::get_locked_amount(i, @campaign_manager);
                vector::push_back(&mut campaigns, camp);
            };
            i = i + 1;
        };
        campaigns
    }

    // Returns the unit price of a campaign
    #[view]
    public fun get_unit_price(campaign_id: u64): u64 acquires CampaignStore {
        let campaign = get_campaign(campaign_id);
        campaign.unit_price
    }

    #[test_only]
    public fun initialize_for_test(account: &signer) {
        init_module(account);
    }

    #[test_only]
    use aptos_framework::account;
    #[test_only]
    use aptos_framework::aptos_coin;
    #[test_only]
    use aptos_framework::coin;

    #[test]
    fun test_create_campaign() acquires CampaignStore {
        // Test hesaplarini olustur
        let test_account = account::create_account_for_test(@0x1);
        let campaign_manager = account::create_account_for_test(@campaign_manager);
        let escrow_manager = account::create_account_for_test(@escrow_manager);
        
        // AptosCoin'i baslat
        let framework_signer = account::create_account_for_test(@0x1);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework_signer);

        // Test hesaplari icin coin kaydi olustur ve bakiye ekle
        coin::register<aptos_coin::AptosCoin>(&test_account);
        let coins = coin::mint<aptos_coin::AptosCoin>(10000, &mint_cap);
        coin::deposit(signer::address_of(&test_account), coins);
        
        // Modulleri baslat
        init_module(&campaign_manager);
        EscrowManager::initialize_for_test(&escrow_manager);
        
        // Test verilerini hazirla
        let title = b"Test Campaign";
        let description = b"Test Description";
        let data_spec = b"Test Data Spec";
        let unit_price = 100;
        let reward_pool = 1000;
        
        // Kampanya olustur
        create_campaign(&test_account, title, description, data_spec, unit_price, reward_pool);
        
        // Kampanyayi kontrol et
        let campaign = get_campaign(1);
        assert!(campaign.creator == signer::address_of(&test_account), 1);
        assert!(campaign.unit_price == unit_price, 2);
        assert!(campaign.reward_pool == reward_pool, 3);
        assert!(campaign.active == true, 4);

        // Yetenekleri temizle
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test]
    fun test_get_all_campaigns() acquires CampaignStore {
        // Test hesaplarini olustur
        let test_account = account::create_account_for_test(@0x1);
        let campaign_manager = account::create_account_for_test(@campaign_manager);
        let escrow_manager = account::create_account_for_test(@escrow_manager);
        
        // AptosCoin'i baslat
        let framework_signer = account::create_account_for_test(@0x1);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework_signer);

        // Test hesaplari icin coin kaydi olustur ve bakiye ekle
        coin::register<aptos_coin::AptosCoin>(&test_account);
        let coins = coin::mint<aptos_coin::AptosCoin>(20000, &mint_cap);
        coin::deposit(signer::address_of(&test_account), coins);
        
        // Modulleri baslat
        init_module(&campaign_manager);
        EscrowManager::initialize_for_test(&escrow_manager);
        
        // Iki kampanya olustur
        create_campaign(
            &test_account,
            b"Campaign 1",
            b"Description 1",
            b"Data Spec 1",
            100,
            1000
        );
        
        create_campaign(
            &test_account,
            b"Campaign 2",
            b"Description 2",
            b"Data Spec 2",
            200,
            2000
        );
        
        // Tum kampanyalari al ve kontrol et
        let campaigns = get_all_campaigns();
        assert!(vector::length(&campaigns) == 2, 1);
        
        let campaign1 = vector::borrow(&campaigns, 0);
        let campaign2 = vector::borrow(&campaigns, 1);
        
        assert!(campaign1.unit_price == 100, 2);
        assert!(campaign2.unit_price == 200, 3);
        assert!(campaign1.reward_pool == 1000, 4);
        assert!(campaign2.reward_pool == 2000, 5);

        // Yetenekleri temizle
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test]
    fun test_get_unit_price() acquires CampaignStore {
        // Test hesaplarini olustur
        let test_account = account::create_account_for_test(@0x1);
        let campaign_manager = account::create_account_for_test(@campaign_manager);
        let escrow_manager = account::create_account_for_test(@escrow_manager);
        
        // AptosCoin'i baslat
        let framework_signer = account::create_account_for_test(@0x1);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework_signer);

        // Test hesaplari icin coin kaydi olustur ve bakiye ekle
        coin::register<aptos_coin::AptosCoin>(&test_account);
        let coins = coin::mint<aptos_coin::AptosCoin>(10000, &mint_cap);
        coin::deposit(signer::address_of(&test_account), coins);
        
        // Modulleri baslat
        init_module(&campaign_manager);
        EscrowManager::initialize_for_test(&escrow_manager);
        
        // Test verilerini hazirla
        let unit_price = 150;
        
        // Kampanya olustur
        create_campaign(
            &test_account,
            b"Test Campaign",
            b"Test Description",
            b"Test Data Spec",
            unit_price,
            1000
        );
        
        // Birim fiyati kontrol et
        let price = get_unit_price(1);
        assert!(price == unit_price, 1);

        // Yetenekleri temizle
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test]
    #[expected_failure]
    fun test_nonexistent_campaign() acquires CampaignStore {
        // Test hesaplarini olustur
        let campaign_manager = account::create_account_for_test(@campaign_manager);
        
        // Modulu baslat
        init_module(&campaign_manager);
        
        // Var olmayan kampanyayi sorgula - hata vermeli
        get_campaign(999);
    }
}
