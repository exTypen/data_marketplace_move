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
        coin::transfer<AptosCoin>(account, recipient, amount);
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
} 