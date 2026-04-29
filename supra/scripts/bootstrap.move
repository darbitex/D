// D Supra bootstrap script — converts user's Coin<SupraCoin> to FA, then opens a trove.
//
// Args:
//   supra_amt (u64): raw SUPRA amount for collateral (8 dec).
//                    Must satisfy: supra_amt * price_8dec / 1e8 >= 2 * debt (200% MCR)
//   debt (u64):      raw D to mint (8 dec). Min MIN_DEBT = 0.01 D = 1_000_000.
script {
    use std::signer;
    use supra_framework::coin;
    use supra_framework::primary_fungible_store;
    use supra_framework::supra_coin::SupraCoin;
    use D::D;

    fun bootstrap(user: &signer, supra_amt: u64, debt: u64) {
        // Step 1: Coin<SupraCoin> → FA (Supra's one-way migration direction)
        let c = coin::withdraw<SupraCoin>(user, supra_amt);
        let fa = coin::coin_to_fungible_asset(c);
        primary_fungible_store::deposit(signer::address_of(user), fa);

        // Step 2: Open trove
        D::open_trove(user, supra_amt, debt);
    }
}
