from ape import accounts, project, networks


def main():
    acct = accounts.load("deployer_account")
    priority_fee = networks.active_provider.priority_fee
    max_base_fee = int(networks.active_provider.base_fee * 1.2) + priority_fee
    compass_evm = "0x652Bf77d9F1BDA15B86894a185E8C22d9c722EB4"
    uniswap_v3_nft_manager = "0xC36442b4a4522E871399CD717aBDD847Ab11FE88"
    router = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
    refund_wallet = "0x6dc0A87638CD75Cc700cCdB226c7ab6C054bc70b"
    fee = 10000000000000000
    service_fee_collector = "0xe693603C9441f0e645Af6A5898b76a60dbf757F4"
    service_fee = 0
    project.limit_order_uniswap_v3.deploy(
        compass_evm, uniswap_v3_nft_manager, router, refund_wallet, fee,
        service_fee_collector, service_fee, max_fee=max_base_fee,
        max_priority_fee=priority_fee, sender=acct)
