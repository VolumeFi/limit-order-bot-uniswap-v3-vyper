# pragma version 0.3.10
# pragma optimize gas
# pragma evm-version shanghai
"""
@title Uniswap v3 Limit Order Bot
@license Apache 2.0
@author Volume.finance
"""

struct SwapInfo:
    path: Bytes[224]
    amount: uint256

struct ExactInputParams:
    path: Bytes[224]
    recipient: address
    deadline: uint256
    amountIn: uint256
    amountOutMinimum: uint256

struct Deposit:
    depositor: address
    path: Bytes[224]
    amount: uint256

enum WithdrawType:
    CANCEL
    PROFIT_TAKING
    STOP_LOSS
    EXPIRE

interface ERC20:
    def balanceOf(_owner: address) -> uint256: view
    def approve(_spender: address, _value: uint256) -> bool: nonpayable
    def transfer(_to: address, _value: uint256) -> bool: nonpayable
    def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable

interface WrappedEth:
    def deposit(): payable
    def withdraw(amount: uint256): nonpayable

interface SwapRouter:
    def WETH9() -> address: pure
    def exactInput(params: ExactInputParams) -> uint256: payable

event Deposited:
    deposit_id: uint256
    token0: address
    token1: address
    amount0: uint256
    depositor: address
    profit_taking: uint256
    stop_loss: uint256
    expire: uint256
    is_stable_swap: bool

event Withdrawn:
    deposit_id: uint256
    withdrawer: address
    withdraw_type: WithdrawType
    withdraw_amount: uint256

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

WETH: immutable(address)
VETH: constant(address) = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE # Virtual ETH
MAX_SIZE: constant(uint256) = 8
DENOMINATOR: constant(uint256) = 10 ** 18
ROUTER: immutable(address)
compass: public(address)
deposit_size: public(uint256)
deposits: public(HashMap[uint256, Deposit])
refund_wallet: public(address)
fee: public(uint256)
paloma: public(bytes32)
service_fee_collector: public(address)
service_fee: public(uint256)

@external
def __init__(_compass: address, router: address, _refund_wallet: address, _fee: uint256, _service_fee_collector: address, _service_fee: uint256):
    self.compass = _compass
    ROUTER = router
    WETH = SwapRouter(ROUTER).WETH9()
    self.refund_wallet = _refund_wallet
    self.fee = _fee
    self.service_fee_collector = _service_fee_collector
    self.service_fee = _service_fee
    assert _service_fee < DENOMINATOR, "Wrong service fee amount"
    log UpdateCompass(empty(address), _compass)
    log UpdateRefundWallet(empty(address), _refund_wallet)
    log UpdateFee(0, _fee)
    log UpdateServiceFeeCollector(empty(address), _service_fee_collector)
    log UpdateServiceFee(0, _service_fee)

@internal
def _safe_transfer(_token: address, _to: address, _value: uint256):
    assert ERC20(_token).transfer(_to, _value, default_return_value=True), "Failed transfer"

@internal
def _safe_transfer_from(_token: address, _from: address, _to: address, _value: uint256):
    assert ERC20(_token).transferFrom(_from, _to, _value, default_return_value=True), "Failed transferFrom"

@external
@payable
@nonreentrant("lock")
def deposit(path: Bytes[224], amount0: uint256, profit_taking: uint256, stop_loss: uint256, expire: uint256):
    assert block.timestamp < expire, "Invalidate expire"
    _value: uint256 = msg.value
    _fee: uint256 = self.fee
    if _fee > 0:
        assert _value >= _fee, "Insufficient fee"
        send(self.refund_wallet, _fee)
        _value = unsafe_sub(_value, _fee)
    assert len(path) >= 43, "Path error"
    token0: address = convert(slice(path, 0, 20), address)
    fee_index: uint256 = 20
    amount: uint256 = 0
    if token0 == VETH:
        amount = amount0
        assert _value >= amount, "Insufficient deposit"
        _value = unsafe_sub(_value, amount)
        fee_index = 40
    else:
        amount = ERC20(token0).balanceOf(self)
        self._safe_transfer_from(token0, msg.sender, self, amount)
        amount = ERC20(token0).balanceOf(self) - amount
    if _value > 0:
        send(msg.sender, _value)
    is_stable_swap: bool = True
    for i in range(8):
        if unsafe_add(fee_index, 3) >= len(path):
            break
        fee_level: uint256 = convert(slice(path, fee_index, 3), uint256)
        if fee_level == 0:
            break
        if fee_level > 500:
            is_stable_swap = False
        fee_index = unsafe_add(fee_index, 23)
    _service_fee: uint256 = self.service_fee
    if token0 == VETH:
        if _service_fee > 0:
            _service_fee_amount: uint256 = unsafe_div(amount * _service_fee, DENOMINATOR)
            send(self.service_fee_collector, _service_fee_amount)
            amount = unsafe_sub(amount, _service_fee_amount)
        WrappedEth(WETH).deposit(value=amount)
    else:
        if _service_fee > 0:
            _service_fee_amount: uint256 = unsafe_div(amount * _service_fee, DENOMINATOR)
            self._safe_transfer(token0, self.service_fee_collector, _service_fee_amount)
            amount = unsafe_sub(amount, _service_fee_amount)
    assert amount > 0, "Insufficient deposit"
    deposit_id: uint256 = self.deposit_size
    self.deposits[deposit_id] = Deposit({
        depositor: msg.sender,
        path: path,
        amount: amount,
    })
    self.deposit_size = unsafe_add(deposit_id, 1)
    log Deposited(deposit_id, token0, convert(slice(path, unsafe_sub(len(path), 20), 20), address), amount0, msg.sender, profit_taking, stop_loss, expire, is_stable_swap)

@internal
@nonreentrant("lock")
def _withdraw(deposit_id: uint256, expected: uint256, withdraw_type: WithdrawType) -> uint256:
    deposit: Deposit = self.deposits[deposit_id]
    if withdraw_type == WithdrawType.CANCEL:
        assert msg.sender == deposit.depositor, "Unauthorized"
    self.deposits[deposit_id] = Deposit({
        depositor: empty(address),
        path: empty(Bytes[224]),
        amount: empty(uint256)
    })
    assert deposit.amount > 0, "Empty deposit"
    if withdraw_type == WithdrawType.CANCEL or withdraw_type == WithdrawType.EXPIRE:
        token0: address = convert(slice(deposit.path, 0, 20), address)
        if token0 == VETH:
            WrappedEth(WETH).withdraw(deposit.amount)
            send(deposit.depositor, deposit.amount)
        else:
            self._safe_transfer(token0, deposit.depositor, deposit.amount)
        log Withdrawn(deposit_id, msg.sender, withdraw_type, deposit.amount)
        return deposit.amount
    else:
        _out_amount: uint256 = 0
        _path: Bytes[224] = deposit.path
        token0: address = convert(slice(_path, 0, 20), address)
        token1: address = convert(slice(_path, unsafe_sub(len(_path), 20), 20), address)
        if token0 == VETH:
            _path = slice(_path, 20, unsafe_sub(len(_path), 20))
            WrappedEth(WETH).deposit(value=deposit.amount)
            ERC20(WETH).approve(ROUTER, deposit.amount)
            _out_amount = ERC20(token1).balanceOf(self)
            SwapRouter(ROUTER).exactInput(ExactInputParams({
                path: _path,
                recipient: self,
                deadline: block.timestamp,
                amountIn: deposit.amount,
                amountOutMinimum: expected
            }))
            _out_amount = ERC20(token1).balanceOf(self) - _out_amount
        else:
            assert ERC20(token0).approve(ROUTER, deposit.amount), "Failed approve"
            if token1 == VETH:
                _path = slice(_path, 0, unsafe_sub(len(_path), 20))
                _out_amount = ERC20(WETH).balanceOf(self)
                SwapRouter(ROUTER).exactInput(ExactInputParams({
                    path: _path,
                    recipient: self,
                    deadline: block.timestamp,
                    amountIn: deposit.amount,
                    amountOutMinimum: expected
                }))
                _out_amount = ERC20(WETH).balanceOf(self) - _out_amount
                WrappedEth(WETH).withdraw(_out_amount)
            else:
                _out_amount = ERC20(token1).balanceOf(self)
                SwapRouter(ROUTER).exactInput(ExactInputParams({
                    path: _path,
                    recipient: self,
                    deadline: block.timestamp,
                    amountIn: deposit.amount,
                    amountOutMinimum: expected
                }))
                _out_amount = ERC20(token1).balanceOf(self) - _out_amount
        if token1 == VETH:
            send(deposit.depositor, _out_amount)
        else:
            self._safe_transfer(token1, deposit.depositor, _out_amount)
        log Withdrawn(deposit_id, msg.sender, withdraw_type, _out_amount)
        return _out_amount

@external
def cancel(deposit_id: uint256) -> uint256:
    return self._withdraw(deposit_id, 0, WithdrawType.CANCEL)

@internal
def _paloma_check():
    assert msg.sender == self.compass, "Not compass"
    assert self.paloma == convert(slice(msg.data, unsafe_sub(len(msg.data), 32), 32), bytes32), "Invalid paloma"

@external
def multiple_withdraw(deposit_ids: DynArray[uint256, MAX_SIZE], expected: DynArray[uint256, MAX_SIZE], withdraw_types: DynArray[WithdrawType, MAX_SIZE]):
    self._paloma_check()
    _len: uint256 = len(deposit_ids)
    assert _len == len(expected) and _len == len(withdraw_types), "Validation error"
    for i in range(MAX_SIZE):
        if i >= len(deposit_ids):
            break
        self._withdraw(deposit_ids[i], expected[i], withdraw_types[i])

@external
def withdraw(deposit_id: uint256, withdraw_type: WithdrawType) -> uint256:
    assert msg.sender == empty(address) # this will work as a view function only
    return self._withdraw(deposit_id, 1, withdraw_type)

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
    pass