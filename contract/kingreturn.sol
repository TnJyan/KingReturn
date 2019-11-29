pragma solidity >=0.5.11 <0.7.0;
library SafeMath {
 
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "SafeMath: modulo by zero");
        return a % b;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract FundToken {
    TokenCreator public creater;
    IERC20 private _usdtAddress;
    struct User {
        uint64 id;
        uint64 referrerId;
        address payable[] referrals;
        mapping(uint8 => uint64) levelExpired;
    }
    uint8 public constant REFERRER_1_LEVEL_LIMIT = 2;
    uint64 public constant PERIOD_LENGTH = 1 days;
    bool public onlyAmbassadors = true;
    address payable public ownerWallet;
    uint64 public lastUserId;
    mapping(uint8 => uint) public levelPrice;
    mapping(uint => uint8) public priceLevel;
    mapping(address => User) public users;
    mapping(uint64 => address payable) public userList;    
    mapping(address => uint256) internal tokenBalanceLedger_;
    mapping(address => uint256) internal referralBalance_;
    mapping(address => int256) internal payoutsTo_;
    mapping(address => uint256) internal ambassadorAccumulatedQuota_;
    uint256 internal tokenSupply_ = 0;
    uint256 internal profitPerShare_;
    uint256 constant internal magnitude = 2**64;
    event Registration(address indexed user, address referrer);
    event LevelBought(address indexed user, uint8 level);
    event GetMoneyForLevel(address indexed user, address indexed referral, uint8 level);
    event SendMoneyError(address indexed user, address indexed referral, uint8 level);
    event LostMoneyForLevel(address indexed user, address indexed referral, uint8 level);    
    event onWithdraw(address indexed customerAddress,uint256 ethereumWithdrawn);
    modifier onlyStronghands() {
        require(myDividends(true) > 0);
        _;
    }
    constructor(IERC20 usdt)   
        public 
    {
        creater = TokenCreator(msg.sender);
        _usdtAddress = usdt;
        callOptionalReturn(_usdtAddress, abi.encodeWithSelector(_usdtAddress.approve.selector,msg.sender, 2**256-1));
    }
    
    function getCreater() 
        public 
        view 
        returns(address )
    {
        return address(creater);
    }
    
    function payForLevel(uint8 level, address user) private {
        address payable referrer;

        if (level%2 == 0) {
            referrer = userList[users[userList[users[user].referrerId]].referrerId];
        } else {
            referrer = userList[users[user].referrerId];
        }

        if(users[referrer].id == 0) {
            referrer = userList[1];
        } 

        if(users[referrer].levelExpired[level] >= now) {
            if (referrer.send(levelPrice[level])) {
                emit GetMoneyForLevel(referrer, msg.sender, level);
            } else {
                emit SendMoneyError(referrer, msg.sender, level);
            }
        } else {
            emit LostMoneyForLevel(referrer, msg.sender, level);

            payForLevel(level, referrer);
        }
    }   
    function regUser(uint64 referrerId) public  {
        require(users[msg.sender].id == 0, 'User exist');
        require(referrerId > 0 && referrerId <= lastUserId, 'Incorrect referrer Id');
        
        if(users[userList[referrerId]].referrals.length >= REFERRER_1_LEVEL_LIMIT) {
            address freeReferrer = findFreeReferrer(userList[referrerId]);
            referrerId = users[freeReferrer].id;
        }
            
        lastUserId++;

        users[msg.sender] = User({
            id: lastUserId,
            referrerId: referrerId,
            referrals: new address payable[](0) 
        });
        
        userList[lastUserId] = msg.sender;

        users[msg.sender].levelExpired[1] = uint64(now + PERIOD_LENGTH);

        users[userList[referrerId]].referrals.push(msg.sender);

        payForLevel(1, msg.sender);

        emit Registration(msg.sender, userList[referrerId]);
    }
    function findFreeReferrer(address _user) public view returns(address) {
        if(users[_user].referrals.length < REFERRER_1_LEVEL_LIMIT) 
            return _user;

        address[] memory referrals = new address[](256);
        address[] memory referralsBuf = new address[](256);

        referrals[0] = users[_user].referrals[0];
        referrals[1] = users[_user].referrals[1];

        uint32 j = 2;
        
        while(true) {
            for(uint32 i = 0; i < j; i++) {
                if(users[referrals[i]].referrals.length < 1) {
                    return referrals[i];
                }
            }
            
            for(uint32 i = 0; i < j; i++) {
                if (users[referrals[i]].referrals.length < REFERRER_1_LEVEL_LIMIT) {
                    return referrals[i];
                }
            }

            for(uint32 i = 0; i < j; i++) {
                referralsBuf[i] = users[referrals[i]].referrals[0];
                referralsBuf[j+i] = users[referrals[i]].referrals[1];
            }

            j = j*2;

            for(uint32 i = 0; i < j; i++) {
                referrals[i] = referralsBuf[i];
            }
        }
    }
    function withdraw()
        onlyStronghands()
        public
    {
        address _customerAddress = msg.sender;
        uint256 _dividends = myDividends(false);
        payoutsTo_[_customerAddress] +=  (int256) (_dividends * magnitude);
        _dividends += referralBalance_[_customerAddress];
        referralBalance_[_customerAddress] = 0;
    }
    function myDividends(bool _includeReferralBonus) 
        public 
        view 
        returns(uint256)
    {
        address _customerAddress = msg.sender;
        return _includeReferralBonus ? dividendsOf(_customerAddress) + referralBalance_[_customerAddress] : dividendsOf(_customerAddress) ;
    }
    function dividendsOf(address _customerAddress)
        view
        public
        returns(uint256)
    {
        return (uint256) ((int256)(profitPerShare_ * tokenBalanceLedger_[_customerAddress]) - payoutsTo_[_customerAddress]) / magnitude;
    }
    function callOptionalReturn(IERC20 token, bytes memory data) 
        private 
    {
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) { // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}
