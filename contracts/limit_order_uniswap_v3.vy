# pragma version 0.3.10
# pragma optimize gas
# pragma evm-version shanghai

struct Deposit:
    pool: address
    token0: address
    token1: address
    from_tick: int24
    to_tick: int24
    depositor: address
    token_id: uint256

struct MintParams:
    token0: address
    token1: address
    fee: uint24
    tickLower: int24
    tickUpper: int24
    amount0Desired: uint256
    amount1Desired: uint256
    amount0Min: uint256
    amount1Min: uint256
    recipient: address
    deadline: uint256

struct DecreaseLiquidityParams:
    tokenId: uint256
    liquidity: uint128
    amount0Min: uint256
    amount1Min: uint256
    deadline: uint256

struct CollectParams:
    tokenId: uint256
    recipient: address
    amount0Max: uint128
    amount1Max: uint128

interface WrappedEth:
    def deposit(): payable
    def withdraw(amount: uint256): nonpayable

interface NonfungiblePositionManager:
    def factory() -> address: view
    def WETH9() -> address: view
    def mint(params: MintParams) -> (uint256, uint128, uint256, uint256): payable
    def decreaseLiquidity(params: DecreaseLiquidityParams) -> (uint256, uint256): payable
    def collect(params: CollectParams) -> (uint256, uint256): payable
    def burn(tokenId: uint256): payable

interface Factory:
    def getPool(tokenA: address, tokenB: address, fee: uint24) -> address: view
    def feeAmountTickSpacing(fee: uint24) -> int24: view

interface ERC20:
    def balanceOf(_owner: address) -> uint256: view
    def transfer(_to: address, _value: uint256) -> bool: nonpayable
    def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable
    def approve(_spender: address, _value: uint256) -> bool: nonpayable

NONFUNGIBLE_POSITION_MANAGER: immutable(address)
FACTORY: immutable(address)
WETH: immutable(address)
VETH: constant(address) = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
MAX_SIZE: constant(uint256) = 8
DENOMINATOR: constant(uint256) = 10 ** 18

event Deposited:
    token_id: indexed(uint256)
    depositor: indexed(address)
    amount: uint256
    pool: indexed(address)
    from_tick: int24
    to_tick: int24

event Withdrawn:
    token_id: indexed(uint256)
    withdrawer: indexed(address)
    recipient: indexed(address)
    amount0: uint256
    amount1: uint256

event UpdateCompass:
    old_compass: address
    new_compass: address

event UpdateRefundWallet:
    old_refund_wallet: address
    new_refund_wallet: address

event UpdateFee:
    old_fee: uint256
    new_fee: uint256

event SetPaloma:
    paloma: bytes32

event UpdateServiceFeeCollector:
    old_service_fee_collector: address
    new_service_fee_collector: address

event UpdateServiceFee:
    old_service_fee: uint256
    new_service_fee: uint256

deposits: public(HashMap[uint256, Deposit])
compass: public(address)
refund_wallet: public(address)
fee: public(uint256)
paloma: public(bytes32)
service_fee_collector: public(address)
service_fee: public(uint256)

@external
def __init__(_compass: address, nonfungible_position_manager: address, _refund_wallet: address, _fee: uint256, _service_fee_collector: address, _service_fee: uint256):
    self.compass = _compass
    self.refund_wallet = _refund_wallet
    self.fee = _fee
    self.service_fee_collector = _service_fee_collector
    self.service_fee = _service_fee
    log UpdateCompass(empty(address), _compass)
    log UpdateRefundWallet(empty(address), _refund_wallet)
    log UpdateFee(0, _fee)
    log UpdateServiceFeeCollector(empty(address), _service_fee_collector)
    log UpdateServiceFee(0, _service_fee)
    NONFUNGIBLE_POSITION_MANAGER = nonfungible_position_manager
    WETH = NonfungiblePositionManager(nonfungible_position_manager).WETH9()
    FACTORY = NonfungiblePositionManager(nonfungible_position_manager).factory()

@internal
def _safe_approve(_token: address, _to: address, _value: uint256):
    assert ERC20(_token).approve(_to, _value, default_return_value=True), "failed approve"

@internal
def _safe_transfer(_token: address, _to: address, _value: uint256):
    assert ERC20(_token).transfer(_to, _value, default_return_value=True), "failed transfer"

@internal
def _safe_transfer_from(_token: address, _from: address, _to: address, _value: uint256):
    assert ERC20(_token).transferFrom(_from, _to, _value, default_return_value=True), "failed transferFrom"

@external
@payable
@nonreentrant('lock')
def deposit(token0: address, amount: uint256, token1: address, fee: uint24, to_tick: int24):
    _value: uint256 = msg.value
    _fee: uint256 = self.fee
    if _fee > 0:
        assert _value >= _fee, "Insufficient fee"
        send(self.refund_wallet, _fee)
        _value = unsafe_sub(_value, _fee)
    tokenA: address = token0
    tokenB: address = token1
    _service_fee: uint256 = self.service_fee
    _amount: uint256 = amount
    if token0 == VETH:
        if _value != _amount:
            assert _value > _amount
            send(msg.sender, _value - _amount)
        if _service_fee > 0:
            _service_fee_amount: uint256 = unsafe_div(_amount * _service_fee, DENOMINATOR)
            send(self.service_fee_collector, _service_fee_amount)
            _amount = unsafe_sub(_amount, _service_fee_amount)
        WrappedEth(WETH).deposit(value=_amount)
        tokenA = WETH
    else:
        send(msg.sender, _value)
        orig_balance: uint256 = ERC20(token0).balanceOf(self)
        self._safe_transfer_from(token0, msg.sender, self, _amount)
        assert ERC20(token0).balanceOf(self) == orig_balance + _amount
        if _service_fee > 0:
            _service_fee_amount: uint256 = unsafe_div(_amount * _service_fee, DENOMINATOR)
            self._safe_transfer(token0, self.service_fee_collector, _service_fee_amount)
            _amount = unsafe_sub(_amount, _service_fee_amount)
    if token1 == VETH:
        tokenB = WETH
    pool: address = Factory(FACTORY).getPool(tokenA, tokenB, fee)
    assert pool != empty(address)
    tick_spacing: int24 = Factory(FACTORY).feeAmountTickSpacing(fee)
    assert to_tick % tick_spacing == 0
    response_64: Bytes[64] = raw_call(
        pool,
        method_id("slot0()"),
        max_outsize = 64,
        is_static_call = True
    )

    from_tick: int24 = convert(slice(response_64, 32, 32), int24)
    tokenId: uint256 = 0
    liquidity: uint128 = 0
    amount0: uint256 = 0
    amount1: uint256 = 0
    if convert(tokenA, uint256) < convert(tokenB, uint256):
        from_tick = from_tick / tick_spacing * tick_spacing + tick_spacing
        assert to_tick > from_tick, "Wrong Tick"
    else:
        from_tick = from_tick - 1 / tick_spacing * tick_spacing
        assert to_tick < from_tick, "Wrong Tick"
    
    self._safe_approve(tokenA, NONFUNGIBLE_POSITION_MANAGER, _amount)

    if convert(tokenA, uint256) < convert(tokenB, uint256):
        tokenId, liquidity, amount0, amount1 = NonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).mint(MintParams({
            token0: tokenA,
            token1: tokenB,
            fee: fee,
            tickLower: from_tick,
            tickUpper: to_tick,
            amount0Desired: _amount,
            amount1Desired: 0,
            amount0Min: 1,
            amount1Min: 0,
            recipient: self,
            deadline: block.timestamp
        }))
    else:
        tokenId, liquidity, amount0, amount1 = NonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).mint(MintParams({
            token0: tokenB,
            token1: tokenA,
            fee: fee,
            tickLower: to_tick,
            tickUpper: from_tick,
            amount0Desired: 0,
            amount1Desired: _amount,
            amount0Min: 0,
            amount1Min: 1,
            recipient: self,
            deadline: block.timestamp
        }))
    self.deposits[tokenId] = Deposit({
        pool: pool,
        token0: token0,
        token1: token1,
        from_tick: from_tick,
        to_tick: to_tick,
        depositor: msg.sender,
        token_id: tokenId
    })
    log Deposited(tokenId, msg.sender, _amount, pool, from_tick, to_tick)

@internal
def _withdraw(tokenId: uint256, recipient: address):
    response_256: Bytes[256] = raw_call(
        NONFUNGIBLE_POSITION_MANAGER,
        _abi_encode(tokenId, method_id=method_id("positions(uint256)")),
        max_outsize = 256,
        is_static_call = True
    )
    liquidity: uint128 = convert(slice(response_256, 224, 32), uint128)
    token0: address = convert(slice(response_256, 64, 32), address)
    token1: address = convert(slice(response_256, 96, 32), address)
    NonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).decreaseLiquidity(DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: liquidity,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
    }))
    amount0: uint256 = 0
    amount1: uint256 = 0
    amount0, amount1 = NonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).collect(CollectParams({
        tokenId: tokenId,
        recipient: self,
        amount0Max: max_value(uint128),
        amount1Max: max_value(uint128)
    }))
    NonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).burn(tokenId)
    deposit: Deposit = self.deposits[tokenId]
    self.deposits[tokenId] = Deposit({
        pool: empty(address),
        token0: empty(address),
        token1: empty(address),
        from_tick: 0,
        to_tick: 0,
        depositor: empty(address),
        token_id: 0
    })
    if amount0 > 0:
        if token0 == WETH and (deposit.token0 == VETH or deposit.token1 == VETH):
            WrappedEth(WETH).withdraw(amount0)
            send(deposit.depositor, amount0)
        else:
            self._safe_transfer(token0, recipient, amount0)
    if amount1 > 0:
        if token1 == WETH and (deposit.token0 == VETH or deposit.token1 == VETH):
            WrappedEth(WETH).withdraw(amount1)
            send(deposit.depositor, amount1)
        else:
            self._safe_transfer(token1, recipient, amount1)
    log Withdrawn(tokenId, msg.sender, recipient, amount0, amount1)

@external
@nonreentrant("lock")
def withdraw(tokenId: uint256):
    deposit: Deposit = self.deposits[tokenId]
    response_64: Bytes[64] = raw_call(
        deposit.pool,
        method_id("slot0()"),
        max_outsize = 64,
        is_static_call = True
    )
    tick: int24 = convert(slice(response_64, 32, 32), int24)
    if deposit.from_tick < deposit.to_tick:
        assert tick >= deposit.to_tick
    else:
        assert tick <= deposit.to_tick
    self._withdraw(tokenId, deposit.depositor)

@external
@nonreentrant("lock")
def multiple_withdraw(tokenIds: DynArray[uint256, MAX_SIZE]):
    for tokenId in tokenIds:
        deposit: Deposit = self.deposits[tokenId]
        response_64: Bytes[64] = raw_call(
            deposit.pool,
            method_id("slot0()"),
            max_outsize = 64,
            is_static_call = True
        )
        tick: int24 = convert(slice(response_64, 32, 32), int24)
        if deposit.from_tick < deposit.to_tick:
            assert tick >= deposit.to_tick
        else:
            assert tick <= deposit.to_tick
        self._withdraw(tokenId, deposit.depositor)

@external
@nonreentrant("lock")
def cancel(tokenId: uint256):
    deposit: Deposit = self.deposits[tokenId]
    assert deposit.depositor == msg.sender
    self._withdraw(tokenId, deposit.depositor)

@external
@nonreentrant("lock")
def multiple_cancel(tokenIds: DynArray[uint256, MAX_SIZE]):
    for tokenId in tokenIds:
        deposit: Deposit = self.deposits[tokenId]
        assert deposit.depositor == msg.sender
        self._withdraw(tokenId, deposit.depositor)

@internal
def _paloma_check():
    assert msg.sender == self.compass, "Not compass"
    assert self.paloma == convert(slice(msg.data, unsafe_sub(len(msg.data), 32), 32), bytes32), "Invalid paloma"

@external
def update_compass(new_compass: address):
    self._paloma_check()
    self.compass = new_compass
    log UpdateCompass(msg.sender, new_compass)

@external
def update_refund_wallet(new_refund_wallet: address):
    self._paloma_check()
    old_refund_wallet: address = self.refund_wallet
    self.refund_wallet = new_refund_wallet
    log UpdateRefundWallet(old_refund_wallet, new_refund_wallet)

@external
def update_fee(new_fee: uint256):
    self._paloma_check()
    old_fee: uint256 = self.fee
    self.fee = new_fee
    log UpdateFee(old_fee, new_fee)

@external
def set_paloma():
    assert msg.sender == self.compass and self.paloma == empty(bytes32) and len(msg.data) == 36, "Invalid"
    _paloma: bytes32 = convert(slice(msg.data, 4, 32), bytes32)
    self.paloma = _paloma
    log SetPaloma(_paloma)

@external
def update_service_fee_collector(new_service_fee_collector: address):
    self._paloma_check()
    self.service_fee_collector = new_service_fee_collector
    log UpdateServiceFeeCollector(msg.sender, new_service_fee_collector)

@external
def update_service_fee(new_service_fee: uint256):
    self._paloma_check()
    assert new_service_fee < DENOMINATOR, "Wrong service fee"
    old_service_fee: uint256 = self.service_fee
    self.service_fee = new_service_fee
    log UpdateServiceFee(old_service_fee, new_service_fee)

@external
@payable
def __default__():
    assert msg.sender == WETH