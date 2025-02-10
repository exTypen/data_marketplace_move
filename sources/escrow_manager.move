module escrow_manager::EscrowManager {
    use std::signer;
    use std::table::{Self, Table};
    use aptos_framework::coin::{Self};
    use aptos_framework::aptos_coin::AptosCoin;

    friend contribution_manager::ContributionManager;

    /// Escrow structure
    struct EscrowStore has key {
        escrows: Table<u64, u64>, // campaign_id -> amount
    }

    /// Error codes
    const ERR_NOT_ENOUGH_BALANCE: u64 = 1;
    const ERR_ESCROW_NOT_FOUND: u64 = 2;
    const ERR_UNAUTHORIZED: u64 = 3;

    /// Automatically runs when the module is initialized
    fun init_module(account: &signer) {
        let store = EscrowStore {
            escrows: table::new(),
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

        // Transfer the funds
        coin::transfer<AptosCoin>(account, store_addr, amount);

        // Create the escrow record
        let store = borrow_global_mut<EscrowStore>(store_addr);
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
        account: &signer,
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

        // Transfer the funds to the recipient
        coin::transfer<AptosCoin>(account, recipient, amount);
    }

    // Displays the amount of locked funds
    #[view]
    public fun get_locked_amount(campaign_id: u64, store_addr: address): u64 acquires EscrowStore {
        let store = borrow_global<EscrowStore>(store_addr);
        assert!(table::contains(&store.escrows, campaign_id), ERR_ESCROW_NOT_FOUND);
        *table::borrow(&store.escrows, campaign_id)
    }
} 