from brownie import limit_order_uniswap_v3, accounts


def main():
    acct = accounts.load("deployer_account")
    compass_evm = ""
    uniswap_v3_nft_manager = ""
    limit_order_uniswap_v3.deploy(
        compass_evm,
        uniswap_v3_nft_manager,
        {"from": acct}
    )
