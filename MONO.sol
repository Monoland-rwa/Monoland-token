// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract MONO is ERC20, Ownable, ERC20Burnable {
    using SafeMath for uint256;
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct TraderInfo {
        uint256 lastTrade;
        uint256 amount;
    }

    string private constant _name = "Monoland";
    string private constant _symbol = "MONO";
    uint8 private constant _decimals = 18;

    uint256 private _totalSupply = 1000000000 * 10 ** uint256(_decimals);
    uint256 private _tFeeTotal;
    uint256 private _tBurnTotal;

    bool public isAntiWhale;
    uint256 public maxBuy = 300000000000000000000;
    uint256 public maxSell = 150000000000000000000;
    address public pancakeLiquidPair;
    address private feeReceiver;
    uint256 public buyCooldown = 0 minutes;
    uint256 public sellCooldown = 0 minutes;
    uint256 public sellFeePercent = 3;
    uint256 public buyFeePercent = 0;
    uint256 public constant MAX_LIQUIDITY_MINT = 100000000 * 10 ** uint256(_decimals);
    uint256 public constant MAX_FARMING_MINT = 530000000 * 10 ** uint256(_decimals);
    uint256 public totalMintedForLiquidity;
    uint256 public totalMintedForFarming;


    mapping(address => mapping(string => TraderInfo)) private traders;
    mapping(address => bool) public blacklist;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _balances;
    mapping(address => bool) private feeExempts;
    EnumerableSet.AddressSet private feeExemptAddresses;
    mapping(address => bool) private liquidityMinters;
    EnumerableSet.AddressSet private liquidityMinterAddresses;

    mapping(address => bool) private farmingMinters;
    EnumerableSet.AddressSet private farmingMinterAddresses;

    event MintForLiquidity(address indexed to, uint256 amount);
    event MintForFarming(address indexed to, uint256 amount);

    constructor() ERC20(_name, _symbol) {
        _balances[_msgSender()] = _balances[_msgSender()].add(_totalSupply * 37 / 100);
        emit Transfer(address(0), _msgSender(), _totalSupply * 37 / 100);

    }
    modifier onlyLiquidityMinter() {
        require(liquidityMinters[msg.sender] || msg.sender == owner(), "Not a liquidity minter");
        _;
    }
    modifier onlyFarmingMinter() {
        require(farmingMinters[msg.sender] || msg.sender == owner(), "Not a farming minter");
        _;
    }

    function mintForLiquidity(address to, uint256 amount) external onlyLiquidityMinter returns (uint256){
        require(
            totalMintedForLiquidity + amount <= MAX_LIQUIDITY_MINT,
            "Exceeds liquidity mint limit"
        );
        totalMintedForLiquidity += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
        emit MintForLiquidity(to, amount);
        return amount;
    }

    function mintForFarming(address to, uint256 amount) external onlyFarmingMinter returns (uint256) {
        require(
            totalMintedForFarming + amount <= MAX_FARMING_MINT,
            "Exceeds farming mint limit"
        );
        totalMintedForFarming += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
        emit MintForFarming(to, amount);
        return amount;
    }

    function addLiquidityMinter(address account) external onlyOwner {
        require(!liquidityMinters[account], "Already a liquidity minter");
        liquidityMinters[account] = true;
        if (!liquidityMinterAddresses.contains(account)) {
            liquidityMinterAddresses.add(account);
        }
    }

    function removeLiquidityMinter(address account) external onlyOwner {
        require(liquidityMinters[account], "Not a liquidity minter");
        liquidityMinters[account] = false;
        if (liquidityMinterAddresses.contains(account)) {
            liquidityMinterAddresses.remove(account);
        }
    }

    function addFarmingMinter(address account) external onlyOwner {
        require(!farmingMinters[account], "Already a farming minter");
        farmingMinters[account] = true;
        if (!farmingMinterAddresses.contains(account)) {
            farmingMinterAddresses.add(account);
        }
    }

    function removeFarmingMinter(address account) external onlyOwner {
        require(farmingMinters[account], "Not a farming minter");
        farmingMinters[account] = false;
        if (farmingMinterAddresses.contains(account)) {
            farmingMinterAddresses.remove(account);
        }
    }

    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        feeReceiver = _feeReceiver;
    }

    function multiBlacklist(address[] memory addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            blacklist[addresses[i]] = true;
        }
    }

    function multiRemoveFromBlacklist(address[] memory addresses)
    external
    onlyOwner
    {
        for (uint256 i = 0; i < addresses.length; i++) {
            blacklist[addresses[i]] = false;
        }
    }

    function multiTransfer(address[] memory receivers, uint256[] memory amounts)
    public
    {
        require(receivers.length == amounts.length, "Mismatched arrays");
        for (uint256 i = 0; i < receivers.length; i++) {
            transfer(receivers[i], amounts[i]);
        }
    }

    function allowance(address owner, address spender)
    public
    view
    override
    returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
    public
    override
    returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual override {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function increaseAllowance(address spender, uint256 addedValue)
    public
    virtual
    override
    returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
    public
    virtual
    override
    returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function transfer(address recipient, uint256 amount)
    public
    override
    returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }


    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(
            amount <= _balances[sender],
            "ERC20: amount must be less or equal to balance"
        );
        require(!blacklist[sender] && !blacklist[recipient]);

        if (isAntiWhale) {
            antiWhale(sender, recipient, amount);
        }

        uint256 feeAmount = 0;

        if (feeReceiver != address(0)) {
            if (sender == pancakeLiquidPair && recipient != owner() && !feeExempts[recipient]) {
                feeAmount = (amount * buyFeePercent) / 100;
            } else if (recipient == pancakeLiquidPair && sender != owner() && !feeExempts[sender]) {
                feeAmount = (amount * sellFeePercent) / 100;
            }
        }
        require(amount > feeAmount, "Transfer amount is too low after fee");
        if (feeAmount > 0) {
            _balances[sender] = _balances[sender].sub(feeAmount);
            _balances[feeReceiver] = _balances[feeReceiver].add(feeAmount);
            emit Transfer(sender, feeReceiver, feeAmount);
        }
        uint256 remainingAmount = amount - feeAmount;
        _balances[sender] = _balances[sender].sub(remainingAmount);
        _balances[recipient] = _balances[recipient].add(remainingAmount);
        emit Transfer(sender, recipient, remainingAmount);
    }


    function burn(uint256 amount) public virtual override onlyOwner {
        _burn(_msgSender(), amount);
    }

    function _burn(address account, uint256 amount) internal override {
        require(amount != 0);
        require(amount <= _balances[account]);
        _totalSupply = _totalSupply.sub(amount);
        _tBurnTotal = _tBurnTotal.add(amount);
        _balances[account] = _balances[account].sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address owner) public view override returns (uint256) {
        return _balances[owner];
    }

    function totalBurn() public view returns (uint256) {
        return _tBurnTotal;
    }

    function setAntiWhale(bool _isAntiWhale) external onlyOwner {
        isAntiWhale = _isAntiWhale;
    }

    function antiWhale(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal {
        uint256 curTime = block.timestamp;
        require(pancakeLiquidPair != address(0), "Liquidity pair not set");
        if (pancakeLiquidPair != address(0)) {
            if (_sender == pancakeLiquidPair) {
                if (_amount > maxBuy) revert("Buy amount limited ");
                else if (traders[_recipient]["BUY"].lastTrade == 0) {
                    traders[_recipient]["BUY"] = TraderInfo({
                        lastTrade: curTime,
                        amount: _amount
                    });
                } else if (
                    traders[_recipient]["BUY"].lastTrade + buyCooldown > curTime
                ) {
                    revert("You are cooldown to next trade!");
                } else {
                    traders[_recipient]["BUY"] = TraderInfo({
                        lastTrade: curTime,
                        amount: _amount
                    });
                }
            } else {
                if (_amount > maxSell) revert("Sell amount limited ");
                else if (traders[_sender]["SELL"].lastTrade == 0) {
                    traders[_sender]["SELL"] = TraderInfo({
                        lastTrade: curTime,
                        amount: _amount
                    });
                } else if (
                    traders[_sender]["SELL"].lastTrade + sellCooldown > curTime
                ) {
                    revert("You are cooldown to next trade!");
                } else {
                    traders[_sender]["SELL"] = TraderInfo({
                        lastTrade: curTime,
                        amount: _amount
                    });
                }
            }
        } else {
            if (_amount > maxBuy) revert("Buy amount limited ");
        }
    }

    function setBuyCooldown(uint256 _duration) external onlyOwner {
        buyCooldown = _duration;
    }

    function setSellCooldown(uint256 _duration) external onlyOwner {
        sellCooldown = _duration;
    }

    function setMaxBuy(uint256 _maxBuy) external onlyOwner {
        maxBuy = _maxBuy;
    }

    function setMaxSell(uint256 _maxSell) external onlyOwner {
        maxSell = _maxSell;
    }

    function setLiquidPair(address _lp) external onlyOwner {
        pancakeLiquidPair = _lp;
    }

    function addFeeExempt(address account) external onlyOwner {
        require(!feeExempts[account], "Address is already fee exempt");
        feeExempts[account] = true;
        if (!feeExemptAddresses.contains(account)) {
            feeExemptAddresses.add(account);
        }
    }

    function multiAddFeeExempt(address[] memory accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            if (!feeExempts[account]) {
                feeExempts[account] = true;
                if (!feeExemptAddresses.contains(account)) {
                    feeExemptAddresses.add(account);
                }
            }
        }
    }

    function removeFeeExempt(address account) external onlyOwner {
        require(feeExempts[account], "Address is not fee exempt");
        feeExempts[account] = false;

        if (feeExemptAddresses.contains(account)) {
            feeExemptAddresses.remove(account);
        }

    }

    function multiRemoveFeeExempt(address[] memory accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            if (feeExempts[account]) {
                feeExempts[account] = false;

                if (feeExemptAddresses.contains(account)) {
                    feeExemptAddresses.remove(account);
                }
            }
        }
    }

    function getFeeExemptAddresses() external view onlyOwner returns (address[] memory) {
        return feeExemptAddresses.values();
    }

    function getLiquidityMinterAddresses() external view onlyOwner returns (address[] memory) {
        return liquidityMinterAddresses.values();
    }

    function getFarmingMinterAddresses() external view onlyOwner returns (address[] memory) {
        return farmingMinterAddresses.values();
    }

    function getFeeReceiver() external view onlyOwner returns (address) {
        return feeReceiver;
    }

    function setSellFeePercent(uint256 _sellFeePercent) external onlyOwner {
        require(_sellFeePercent <= 100, "Fee percent cannot exceed 100%");
        sellFeePercent = _sellFeePercent;
    }

    function setBuyFeePercent(uint256 _buyFeePercent) external onlyOwner {
        require(_buyFeePercent <= 100, "Fee percent cannot exceed 100%");
        buyFeePercent = _buyFeePercent;
    }
}
