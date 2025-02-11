module escrow_manager::EscrowManager {
    use std::signer;
    use std::table::{Self, Table};
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account;

    friend contribution_manager::ContributionManager;

    /// Escrow structure
    struct EscrowStore has key {
        escrows: Table<u64, u64>, // campaign_id -> amount
        signer_cap: account::SignerCapability,
    }

    /// Error codes
    const ERR_NOT_ENOUGH_BALANCE: u64 = 1;
    const ERR_ESCROW_NOT_FOUND: u64 = 2;
    const ERR_UNAUTHORIZED: u64 = 3;

    /// Automatically runs when the module is initialized
    fun init_module(account: &signer) {
        let (resource_signer, signer_cap) = account::create_resource_account(account, b"escrow_manager");
        
        // Register AptosCoin store for the resource account
        if (!coin::is_account_registered<AptosCoin>(signer::address_of(&resource_signer))) {
            coin::register<AptosCoin>(&resource_signer);
        };

        let store = EscrowStore {
            escrows: table::new(),
            signer_cap,
        };
        move_to(account, store);
    }

    /// Locks funds for a specific campaign
    public fun lock_funds(
        account: &signer,
        campaign_id: u64,
        amount: u64,
        store_addr: address
    ) acquires EscrowStore {
        // Check if the user has enough balance
        assert!(coin::balance<AptosCoin>(signer::address_of(account)) >= amount, ERR_NOT_ENOUGH_BALANCE);

        let store = borrow_global_mut<EscrowStore>(store_addr);
        let resource_signer = account::create_signer_with_capability(&store.signer_cap);
        let resource_addr = signer::address_of(&resource_signer);

        // Transfer the funds to resource account
        coin::transfer<AptosCoin>(account, resource_addr, amount);

        // Create the escrow record
        table::add(&mut store.escrows, campaign_id, amount);
    }

    /// Releases locked funds
    public fun release_funds(
        account: &signer,
        campaign_id: u64,
        recipient: address,
        store_addr: address
    ) acquires EscrowStore {
        let store = borrow_global_mut<EscrowStore>(store_addr);
        
        // Check if there are locked funds for the campaign
        assert!(table::contains(&store.escrows, campaign_id), ERR_ESCROW_NOT_FOUND);
        
        // Only the store owner can release the funds
        assert!(signer::address_of(account) == store_addr, ERR_UNAUTHORIZED);

        let amount = table::remove(&mut store.escrows, campaign_id);
        let resource_signer = account::create_signer_with_capability(&store.signer_cap);
        coin::transfer<AptosCoin>(&resource_signer, recipient, amount);
    }

    /// Releases funds for data contribution
    public(friend) fun release_funds_for_data(
        campaign_id: u64,
        recipient: address,
        store_addr: address,
        amount: u64
    ) acquires EscrowStore {
        let store = borrow_global_mut<EscrowStore>(store_addr);
        
        // Check if there are locked funds for the campaign
        assert!(table::contains(&store.escrows, campaign_id), ERR_ESCROW_NOT_FOUND);

        let locked_amount = *table::borrow(&store.escrows, campaign_id);
        assert!(locked_amount >= amount, ERR_NOT_ENOUGH_BALANCE);

        // Update the locked amount
        table::upsert(&mut store.escrows, campaign_id, locked_amount - amount);

        // Transfer directly from store_addr
        let account_signer = account::create_signer_with_capability(&store.signer_cap);
        coin::transfer<AptosCoin>(&account_signer, recipient, amount);
    }

    // Displays the amount of locked funds
    #[view]
    public fun get_locked_amount(campaign_id: u64, store_addr: address): u64 acquires EscrowStore {
        let store = borrow_global<EscrowStore>(store_addr);
        assert!(table::contains(&store.escrows, campaign_id), ERR_ESCROW_NOT_FOUND);
        *table::borrow(&store.escrows, campaign_id)
    }

    #[test_only]
    public fun initialize_for_test(account: &signer) {
        init_module(account);
    }

    #[test_only]
    use aptos_framework::aptos_coin;

    #[test]
    fun test_lock_funds() acquires EscrowStore {
        // Test hesaplarini olustur
        let test_account = account::create_account_for_test(@0x1);
        let escrow_manager = account::create_account_for_test(@escrow_manager);
        
        // AptosCoin'i baslat
        let framework_signer = account::create_account_for_test(@0x1);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework_signer);

        // Test hesaplari icin coin kaydi olustur ve bakiye ekle
        coin::register<aptos_coin::AptosCoin>(&test_account);
        coin::register<aptos_coin::AptosCoin>(&escrow_manager);
        let coins = coin::mint<aptos_coin::AptosCoin>(10000, &mint_cap);
        coin::deposit(signer::address_of(&test_account), coins);
        
        // Modulu baslat ve resource account'u kaydet
        init_module(&escrow_manager);
        let store = borrow_global<EscrowStore>(@escrow_manager);
        let resource_signer = account::create_signer_with_capability(&store.signer_cap);
        if (!coin::is_account_registered<AptosCoin>(signer::address_of(&resource_signer))) {
            coin::register<AptosCoin>(&resource_signer);
        };
        
        // Test verilerini hazirla
        let campaign_id = 1;
        let amount = 1000;
        
        // Fonlari kilitle
        lock_funds(&test_account, campaign_id, amount, @escrow_manager);
        
        // Kilitli miktari kontrol et
        let locked_amount = get_locked_amount(campaign_id, @escrow_manager);
        assert!(locked_amount == amount, 1);

        // Yetenekleri temizle
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test]
    fun test_release_funds() acquires EscrowStore {
        // Test hesaplarini olustur
        let test_account = account::create_account_for_test(@0x1);
        let recipient = account::create_account_for_test(@0x2);
        let escrow_manager = account::create_account_for_test(@escrow_manager);
        
        // AptosCoin'i baslat
        let framework_signer = account::create_account_for_test(@0x1);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework_signer);

        // Test hesaplari icin coin kaydi olustur ve bakiye ekle
        coin::register<aptos_coin::AptosCoin>(&test_account);
        coin::register<aptos_coin::AptosCoin>(&recipient);
        coin::register<aptos_coin::AptosCoin>(&escrow_manager);
        let coins = coin::mint<aptos_coin::AptosCoin>(10000, &mint_cap);
        coin::deposit(signer::address_of(&test_account), coins);
        
        // Modulu baslat ve resource account'u kaydet
        init_module(&escrow_manager);
        let store = borrow_global<EscrowStore>(@escrow_manager);
        let resource_signer = account::create_signer_with_capability(&store.signer_cap);
        if (!coin::is_account_registered<AptosCoin>(signer::address_of(&resource_signer))) {
            coin::register<AptosCoin>(&resource_signer);
        };
        
        // Test verilerini hazirla
        let campaign_id = 1;
        let amount = 1000;
        
        // Fonlari kilitle
        lock_funds(&test_account, campaign_id, amount, @escrow_manager);
        
        // Fonlari serbest birak
        release_funds(&escrow_manager, campaign_id, signer::address_of(&recipient), @escrow_manager);
        
        // Bakiyeleri kontrol et
        let recipient_balance = coin::balance<aptos_coin::AptosCoin>(signer::address_of(&recipient));
        assert!(recipient_balance == amount, 1);

        // Yetenekleri temizle
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test]
    fun test_release_funds_for_data() acquires EscrowStore {
        // Test hesaplarini olustur
        let test_account = account::create_account_for_test(@0x1);
        let contributor = account::create_account_for_test(@0x2);
        let escrow_manager = account::create_account_for_test(@escrow_manager);
        
        // AptosCoin'i baslat
        let framework_signer = account::create_account_for_test(@0x1);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework_signer);

        // Test hesaplari icin coin kaydi olustur ve bakiye ekle
        coin::register<aptos_coin::AptosCoin>(&test_account);
        coin::register<aptos_coin::AptosCoin>(&contributor);
        coin::register<aptos_coin::AptosCoin>(&escrow_manager);
        let coins = coin::mint<aptos_coin::AptosCoin>(10000, &mint_cap);
        coin::deposit(signer::address_of(&test_account), coins);
        
        // Modulu baslat ve resource account'u kaydet
        init_module(&escrow_manager);
        let store = borrow_global<EscrowStore>(@escrow_manager);
        let resource_signer = account::create_signer_with_capability(&store.signer_cap);
        if (!coin::is_account_registered<AptosCoin>(signer::address_of(&resource_signer))) {
            coin::register<AptosCoin>(&resource_signer);
        };
        
        // Test verilerini hazirla
        let campaign_id = 1;
        let total_amount = 1000;
        let release_amount = 500;
        
        // Fonlari kilitle
        lock_funds(&test_account, campaign_id, total_amount, @escrow_manager);
        
        // Veri katkisi icin fonlari serbest birak
        release_funds_for_data(campaign_id, signer::address_of(&contributor), @escrow_manager, release_amount);
        
        // Bakiyeleri ve kalan kilitli miktari kontrol et
        let contributor_balance = coin::balance<aptos_coin::AptosCoin>(signer::address_of(&contributor));
        let remaining_locked = get_locked_amount(campaign_id, @escrow_manager);
        assert!(contributor_balance == release_amount, 1);
        assert!(remaining_locked == total_amount - release_amount, 2);

        // Yetenekleri temizle
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test]
    #[expected_failure(abort_code = ERR_ESCROW_NOT_FOUND, location = Self)]
    fun test_get_locked_amount_nonexistent_campaign() acquires EscrowStore {
        // Test hesabini olustur
        let escrow_manager = account::create_account_for_test(@escrow_manager);
        
        // AptosCoin'i baslat
        let framework_signer = account::create_account_for_test(@0x1);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(&framework_signer);

        // Escrow hesabi icin coin kaydi olustur
        coin::register<aptos_coin::AptosCoin>(&escrow_manager);
        
        // Modulu baslat ve resource account'u kaydet
        init_module(&escrow_manager);
        let store = borrow_global<EscrowStore>(@escrow_manager);
        let resource_signer = account::create_signer_with_capability(&store.signer_cap);
        if (!coin::is_account_registered<AptosCoin>(signer::address_of(&resource_signer))) {
            coin::register<AptosCoin>(&resource_signer);
        };
        
        // Var olmayan kampanya icin kilitli miktari kontrol et
        get_locked_amount(999, @escrow_manager);

        // Yetenekleri temizle
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }
} 