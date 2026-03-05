    // SPDX-License-Identifier: MIT
    pragma solidity ^0.8.0;

    library TransferHelper {
        function safeTransfer(address token, address to, uint256 value) internal {
            (bool success, bytes memory data) = token.call(
                abi.encodeWithSelector(0xa9059cbb, to, value)
            );
            require(
                success && (data.length == 0 || abi.decode(data, (bool))),
                "TransferHelper: TRANSFER_FAILED"
            );
        }

        function safeTransferFrom(
            address token,
            address from,
            address to,
            uint256 value
        ) internal {
            (bool success, bytes memory data) = token.call(
                abi.encodeWithSelector(0x23b872dd, from, to, value)
            );
            require(
                success && (data.length == 0 || abi.decode(data, (bool))),
                "TransferHelper: TRANSFER_FROM_FAILED"
            );
        }

        function safeTransferETH(address to, uint256 value) internal {
            (bool success, ) = to.call{value: value}(new bytes(0));
            require(success, "TransferHelper: ETH_TRANSFER_FAILED");
        }
    }

    // Interface 定义
    interface IPortal {
        function newTokenV2(
            Launchpad.NewTokenV2Params calldata params
        ) external payable returns (address token);

        function newTokenV5(
            Launchpad.NewTokenV5Params calldata params
        ) external payable returns (address token);

        function swapExactInput(
            Launchpad.ExactInputParams calldata params
        ) external payable returns (uint256 outputAmount);
    }

    // Portal 状态查询（判断是否已迁移到 DEX，与 AutoBurner 一致）
    interface IPortalView {
        enum TokenStatus {
            Invalid,
            Tradable,
            InDuel,
            Killed,
            DEX,
            Staged
        }

        enum TokenVersion {
            TOKEN_LEGACY_MINT_NO_PERMIT,
            TOKEN_LEGACY_MINT_NO_PERMIT_DUPLICATE,
            TOKEN_V2_PERMIT,
            TOKEN_GOPLUS,
            TOKEN_TAXED,
            TOKEN_TAXED_V2
        }

        struct TokenStateV6 {
            TokenStatus status;
            uint256 reserve;
            uint256 circulatingSupply;
            uint256 price;
            TokenVersion tokenVersion;
            uint256 r;
            uint256 h;
            uint256 k;
            uint256 dexSupplyThresh;
            address quoteTokenAddress;
            bool nativeToQuoteSwapEnabled;
            bytes32 extensionID;
            uint256 taxRate;
            address pool;
            uint256 progress;
        }

        function getTokenV6(address token) external view returns (TokenStateV6 memory state);
    }

    interface IPancakeRouter {
        function swapExactTokensForTokensSupportingFeeOnTransferTokens(
            uint256 amountIn,
            uint256 amountOutMin,
            address[] calldata path,
            address to,
            uint256 deadline
        ) external;
    }

    /// @dev PancakeSwap V3 SwapRouter（0 税代币迁移后走 V3 池）
    interface IPancakeV3Router {
        struct ExactInputSingleParams {
            address tokenIn;
            address tokenOut;
            uint24 fee;
            address recipient;
            uint256 deadline;
            uint256 amountIn;
            uint256 amountOutMinimum;
            uint160 sqrtPriceLimitX96;
        }
        function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256 amountOut);
    }

    contract Launchpad {
        address public constant PORTAL = 0xe2cE6ab80874Fa9Fa2aAE65D277Dd6B8e65C9De0;

        // Enum 定义
        enum DexThreshType {
            TWO_THIRDS,
            FOUR_FIFTHS,
            HALF,
            _95_PERCENT,
            _81_PERCENT,
            _1_PERCENT
        }
        enum MigratorType {
            V3_MIGRATOR,
            V2_MIGRATOR
        }
        enum DEXId {
            DEX0,
            DEX1,
            DEX2
        }
        enum V3LPFeeProfile {
            LP_FEE_PROFILE_STANDARD,
            LP_FEE_PROFILE_LOW,
            LP_FEE_PROFILE_HIGH
        }
        // Struct 定义
        struct NewTokenV2Params {
            string name;
            string symbol;
            string meta;
            DexThreshType dexThresh;
            bytes32 salt;
            uint16 taxRate;
            MigratorType migratorType;
            address quoteToken;
            uint256 quoteAmt;
            address beneficiary;
            bytes permitData;
        }

        struct NewTokenV5Params {
            string name;
            string symbol;
            string meta;
            DexThreshType dexThresh;
            bytes32 salt;
            uint16 taxRate;
            MigratorType migratorType;
            address quoteToken;
            uint256 quoteAmt;
            address beneficiary;
            bytes permitData;
            bytes32 extensionID;
            bytes extensionData;
            DEXId dexId;
            V3LPFeeProfile lpFeeProfile;
            uint64 taxDuration;
            uint64 antiFarmerDuration;
            uint16 mktBps;
            uint16 deflationBps;
            uint16 dividendBps;
            uint16 lpBps;
            uint256 minimumShareBalance;
        }

        struct ExactInputParams {
            address inputToken; // address(0) = native token (BNB)
            address outputToken;
            uint256 inputAmount;
            uint256 minOutputAmount;
            bytes permitData;
        }

        struct TokenCreationData {
            string name;
            string symbol;
            string meta;
            uint16 taxRate;
            uint16 mktBps;
            uint16 deflationBps;
            uint16 lpBps;
            uint16 dividendBps;
            uint256 minimumShareBalance;
            bytes32 extensionID;
            bytes extensionData;
            bytes32 salt;
            address beneficiary;
            address quoteToken;
            uint256 quoteAmt;
        }

        // Event 定义
        event TokenCreated(
            address indexed token,
            string name,
            string symbol,
            uint16 taxRate,
            uint16 dividendBps
        );

        // 内部核心函数
        function _createTokenV2(
            TokenCreationData memory data
        ) private returns (address token) {
            NewTokenV2Params memory params = NewTokenV2Params({
                name: data.name,
                symbol: data.symbol,
                meta: data.meta,
                dexThresh: DexThreshType.FOUR_FIFTHS,
                salt: data.salt,
                taxRate: data.taxRate,
                migratorType: MigratorType.V2_MIGRATOR,
                quoteToken: data.quoteToken,
                quoteAmt: data.quoteAmt,
                beneficiary: data.beneficiary,
                permitData: ""
            });

            token = IPortal(PORTAL).newTokenV2{value: 0}(params);

            emit TokenCreated(token, data.name, data.symbol, data.taxRate, 0);
        }

        function _createTokenV5(
            TokenCreationData memory data
        ) private returns (address token) {
            NewTokenV5Params memory params = NewTokenV5Params({
                name: data.name,
                symbol: data.symbol,
                meta: data.meta,
                dexThresh: DexThreshType.FOUR_FIFTHS,
                salt: data.salt,
                taxRate: data.taxRate,
                migratorType: data.taxRate == 0 ? MigratorType.V3_MIGRATOR : MigratorType.V2_MIGRATOR,
                quoteToken: data.quoteToken,
                quoteAmt: data.quoteAmt,
                beneficiary: data.beneficiary,
                permitData: "",
                extensionID: data.extensionID,
                extensionData: data.extensionData,
                dexId: DEXId.DEX0,
                lpFeeProfile: V3LPFeeProfile.LP_FEE_PROFILE_STANDARD,
                taxDuration: 365 days * 10,
                antiFarmerDuration: 3 days,
                mktBps: data.mktBps,
                deflationBps: data.deflationBps,
                dividendBps: data.dividendBps,
                lpBps: data.lpBps,
                minimumShareBalance: data.minimumShareBalance
            });

            token = IPortal(PORTAL).newTokenV5{value: 0}(params);

            emit TokenCreated(
                token,
                data.name,
                data.symbol,
                data.taxRate,
                data.dividendBps
            );
        }

        /**
         * @dev 创建 V5 代币。taxRate=0 为 0 税标准代币（不校验四档分配，MigratorType=V3_MIGRATOR）；taxRate 1–1000 为税收代币，四档之和须 10000。
         */
        function createToken(
            TokenCreationData memory data
        ) internal returns (address token) {
            require(data.taxRate <= 1000, "Tax rate: 0-1000 bps");
            if (data.taxRate > 0) {
                require(
                    data.mktBps + data.dividendBps + data.deflationBps + data.lpBps == 10000,
                    "mktBps + dividendBps + deflationBps + lpBps must equal 10000"
                );
                if (data.dividendBps > 0) {
                    require(
                        data.minimumShareBalance >= 10_000 ether,
                        "Min share balance >= 10k tokens"
                    );
                }
            }
            token = _createTokenV5(data);
        }

        // 使用 BNB 购买代币（保留供内部或扩展用）
        function _buyTokens(
            address token,
            uint256 ethAmount
        ) internal returns (uint256 tokensReceived) {
            ExactInputParams memory params = ExactInputParams({
                inputToken: address(0), // native BNB
                outputToken: token,
                inputAmount: ethAmount,
                minOutputAmount: 0,
                permitData: bytes("")
            });

            tokensReceived = IPortal(PORTAL).swapExactInput{value: ethAmount}(
                params
            );

            TransferHelper.safeTransfer(token, msg.sender, tokensReceived);
        }
    }

    contract FlapSkill is Launchpad {
        address public constant USDT =
            0x55d398326f99059fF775485246999027B3197955;
        address public constant PANCAKE_ROUTER =
            0x10ED43C718714eb63d5aA57B78B54704E256024E;
        /// @dev PancakeSwap V3 SwapRouter（BSC），0 税代币迁移到 DEX 后走 V3 池；有税代币走 V2 池
        address public constant PANCAKE_V3_ROUTER =
            0x1b81D678ffb9C0263b24A97847620C99d213eB14;
        /// @dev V3 池 fee tier：2500 = 0.25%（若该代币为其他 fee 需改此常量或扩展逻辑）
        uint24 public constant FEE_TIER_V3 = 2500;

        /// @dev 做市/刷量：funder 对某 token 允许的调用地址。仅允许的地址可代表该 funder 对该 token 调用 buyForCaller/sellForCaller，从而区分「小明对 0x0123 刷量」「小红对 0x456 刷量」等不同会话。
        mapping(address funder => mapping(address token => mapping(address caller => bool))) public allowedCallers;

        constructor() {}

        /// @dev 判断代币流动性是否已迁移到 PancakeSwap（与 AutoBurner 一致）
        function _isTokenMigratedToDex(address token) internal view returns (bool) {
            IPortalView.TokenStateV6 memory state = IPortalView(PORTAL).getTokenV6(token);
            return state.status == IPortalView.TokenStatus.DEX;
        }

        /// @dev 是否已迁移且为 0 税（走 V3 池）；有税走 V2 池
        function _isTokenV3Dex(address token) internal view returns (bool) {
            if (!_isTokenMigratedToDex(token)) return false;
            IPortalView.TokenStateV6 memory state = IPortalView(PORTAL).getTokenV6(token);
            return state.taxRate == 0;
        }

        /// @dev 创建 V5 代币。_taxRate=0 为 0 税标准代币（四档参数忽略，salt 用尾号 8888）；_taxRate 1–1000 为税收代币，四档之和须 10000，salt 用尾号 7777。
        /// @param _feeTo 税收受益人（0 税时仍可填，合约会写入）
        /// @param _taxRate 总税点（0 = 0 税，300 = 3%），范围 0–1000
        /// @param _mktBps 营销税点分配（仅 _taxRate>0 时有效，与下三者之和须为 10000）
        /// @param _dividendBps 持币分红税点分配
        /// @param _deflationBps 回购销毁税点分配
        /// @param _lpBps LP 回流税点分配
        /// @param _minimumShareBalance 持币分红最低持仓（仅当 _dividendBps > 0 时需 >= 10_000 ether）
        function createToken(
            string memory _name,
            string memory _symbol,
            string memory _meta,
            address _feeTo,
            bytes32 _salt,
            uint16 _taxRate,
            uint16 _mktBps,
            uint16 _dividendBps,
            uint16 _deflationBps,
            uint16 _lpBps,
            uint256 _minimumShareBalance
        ) external returns (address token) {
            if (_taxRate > 0) {
                require(
                    _mktBps + _dividendBps + _deflationBps + _lpBps == 10000,
                    "mktBps + dividendBps + deflationBps + lpBps must equal 10000"
                );
                if (_dividendBps > 0) {
                    require(
                        _minimumShareBalance >= 10_000 ether,
                        "Min share balance >= 10k tokens when dividendBps > 0"
                    );
                }
            }
            TokenCreationData memory data = TokenCreationData({
                name: _name,
                symbol: _symbol,
                meta: _meta,
                taxRate: _taxRate,
                mktBps: _taxRate == 0 ? 0 : _mktBps,
                deflationBps: _taxRate == 0 ? 0 : _deflationBps,
                lpBps: _taxRate == 0 ? 0 : _lpBps,
                dividendBps: _taxRate == 0 ? 0 : _dividendBps,
                minimumShareBalance: _taxRate == 0 ? 0 : _minimumShareBalance,
                extensionID: bytes32(0),
                extensionData: "",
                salt: _salt,
                beneficiary: _feeTo,
                quoteToken: USDT,
                quoteAmt: 0
            });
            token = createToken(data);
        }

        /// @dev 使用 USDT 购买代币。调用前需先对本合约 approve USDT。若代币已迁移到 PancakeSwap 则走 DEX，否则走 Portal。
        function buyTokens(address _token, uint256 _usdtAmount) external {
            TransferHelper.safeTransferFrom(
                USDT,
                msg.sender,
                address(this),
                _usdtAmount
            );
            _doBuy(_token, _usdtAmount, msg.sender);
        }

        /// @dev 做市/刷量：用 _funder 已授权的 USDT 买入，代币转给调用者。仅 _funder 已对该 _token 登记过的调用地址可调用。做市只有启动与停止，不设磨损上限。
        function buyForCaller(address _token, uint256 _usdtAmount, address _funder) external {
            require(allowedCallers[_funder][_token][msg.sender], "FlapSkill: not allowed caller");
            TransferHelper.safeTransferFrom(USDT, _funder, address(this), _usdtAmount);
            _doBuy(_token, _usdtAmount, msg.sender);
        }

        /// @dev 登记：当前调用者（funder）对某 token 允许哪些地址调用 buyForCaller/sellForCaller。用于区分「小明对 0x0123 刷量」「小红对 0x456 刷量」等，仅被登记地址可动用该 funder 对该 token 的资金。
        function setAllowedCallers(address _token, address[] calldata _callers) external {
            for (uint256 i = 0; i < _callers.length; i++) {
                allowedCallers[msg.sender][_token][_callers[i]] = true;
            }
        }

        /// @dev 取消某 token 下部分地址的调用权限。
        function removeAllowedCallers(address _token, address[] calldata _callers) external {
            for (uint256 i = 0; i < _callers.length; i++) {
                allowedCallers[msg.sender][_token][_callers[i]] = false;
            }
        }

        function _doBuy(
            address _token,
            uint256 _usdtAmount,
            address _recipient
        ) internal {
            if (_isTokenV3Dex(_token)) {
                _approve(USDT, PANCAKE_V3_ROUTER, _usdtAmount);
                IPancakeV3Router(PANCAKE_V3_ROUTER).exactInputSingle(
                    IPancakeV3Router.ExactInputSingleParams({
                        tokenIn: USDT,
                        tokenOut: _token,
                        fee: FEE_TIER_V3,
                        recipient: _recipient,
                        deadline: block.timestamp,
                        amountIn: _usdtAmount,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    })
                );
            } else if (_isTokenMigratedToDex(_token)) {
                _approve(USDT, PANCAKE_ROUTER, _usdtAmount);
                address[] memory path = new address[](2);
                path[0] = USDT;
                path[1] = _token;
                IPancakeRouter(PANCAKE_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    _usdtAmount,
                    0,
                    path,
                    _recipient,
                    block.timestamp
                );
            } else {
                _approve(USDT, PORTAL, _usdtAmount);
                uint256 tokensReceived = _buyTokensWithUSDTInternal(_token, _usdtAmount);
                TransferHelper.safeTransfer(_token, _recipient, tokensReceived);
            }
        }

        function _approve(
            address token,
            address spender,
            uint256 amount
        ) internal {
            (bool success, ) = token.call(
                abi.encodeWithSelector(0x095ea7b3, spender, amount)
            );
            require(success, "Approve failed");
        }

        function _buyTokensWithUSDTInternal(
            address token,
            uint256 usdtAmount
        ) internal returns (uint256 tokensReceived) {
            ExactInputParams memory params = ExactInputParams({
                inputToken: USDT,
                outputToken: token,
                inputAmount: usdtAmount,
                minOutputAmount: 0,
                permitData: bytes("")
            });
            tokensReceived = IPortal(PORTAL).swapExactInput{value: 0}(params);
        }

        /// @dev 卖出代币换 USDT。调用前需先对本合约 approve 要卖出的代币。若代币已迁移到 PancakeSwap 则走 DEX，否则走 Portal。
        /// @param _token 要卖出的代币地址
        /// @param _tokenAmount 卖出数量（代币最小单位）
        function sellTokens(address _token, uint256 _tokenAmount) external {
            TransferHelper.safeTransferFrom(
                _token,
                msg.sender,
                address(this),
                _tokenAmount
            );
            _doSell(_token, _tokenAmount, msg.sender);
        }

        /// @dev 做市/刷量：调用者将代币交给合约卖出，所得 USDT 转给 _funder。仅 _funder 已对该 _token 登记过的调用地址可调用。
        /// 卖出前若数量大于 1 代币，合约先向调用者（worker）转回 1 代币（1e18），再仅将剩余部分卖出，避免 worker 显示清仓。
        function sellForCaller(address _token, uint256 _tokenAmount, address _funder) external {
            require(allowedCallers[_funder][_token][msg.sender], "FlapSkill: not allowed caller");
            TransferHelper.safeTransferFrom(_token, msg.sender, address(this), _tokenAmount);
            uint256 oneToken = 1e18;
            uint256 toSell = _tokenAmount;
            if (_tokenAmount > oneToken) {
                TransferHelper.safeTransfer(_token, msg.sender, oneToken);
                toSell = _tokenAmount - oneToken;
            }
            _doSell(_token, toSell, _funder);
        }

        function _doSell(
            address _token,
            uint256 _tokenAmount,
            address _usdtRecipient
        ) internal returns (uint256 usdtToRecipient) {
            if (_isTokenV3Dex(_token)) {
                _approve(_token, PANCAKE_V3_ROUTER, _tokenAmount);
                usdtToRecipient = IPancakeV3Router(PANCAKE_V3_ROUTER).exactInputSingle(
                    IPancakeV3Router.ExactInputSingleParams({
                        tokenIn: _token,
                        tokenOut: USDT,
                        fee: FEE_TIER_V3,
                        recipient: _usdtRecipient,
                        deadline: block.timestamp,
                        amountIn: _tokenAmount,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    })
                );
            } else if (_isTokenMigratedToDex(_token)) {
                _approve(_token, PANCAKE_ROUTER, _tokenAmount);
                address[] memory path = new address[](2);
                path[0] = _token;
                path[1] = USDT;
                IPancakeRouter(PANCAKE_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    _tokenAmount,
                    0,
                    path,
                    _usdtRecipient,
                    block.timestamp
                );
                usdtToRecipient = 0; // V2 路由不返回数量，磨损统计保守
            } else {
                _approve(_token, PORTAL, _tokenAmount);
                ExactInputParams memory params = ExactInputParams({
                    inputToken: _token,
                    outputToken: USDT,
                    inputAmount: _tokenAmount,
                    minOutputAmount: 0,
                    permitData: bytes("")
                });
                usdtToRecipient = IPortal(PORTAL).swapExactInput{value: 0}(params);
                TransferHelper.safeTransfer(USDT, _usdtRecipient, usdtToRecipient);
            }
        }

        function _balanceOf(address token, address account) internal view returns (uint256) {
            (bool success, bytes memory data) = token.staticcall(
                abi.encodeWithSelector(0x70a08231, account)
            );
            require(success && data.length >= 32, "balanceOf failed");
            return abi.decode(data, (uint256));
        }

        /// @dev 按仓位比例卖出代币换 USDT。合约按调用者当前持仓的 _percentBps/10000 比例计算卖出数量。若代币已迁移到 PancakeSwap 则走 DEX，否则走 Portal。
        /// @param _token 要卖出的代币地址
        /// @param _percentBps 仓位比例，基点（10000 = 100%），如 5000 表示 50%
        function sellTokensByPercent(
            address _token,
            uint256 _percentBps
        ) external returns (uint256 usdtReceived) {
            require(_percentBps > 0 && _percentBps <= 10000, "invalid percent");
            uint256 balance = _balanceOf(_token, msg.sender);
            uint256 amount = (balance * _percentBps) / 10000;
            require(amount > 0, "zero amount");
            TransferHelper.safeTransferFrom(
                _token,
                msg.sender,
                address(this),
                amount
            );
            if (_isTokenV3Dex(_token)) {
                _approve(_token, PANCAKE_V3_ROUTER, amount);
                IPancakeV3Router(PANCAKE_V3_ROUTER).exactInputSingle(
                    IPancakeV3Router.ExactInputSingleParams({
                        tokenIn: _token,
                        tokenOut: USDT,
                        fee: FEE_TIER_V3,
                        recipient: msg.sender,
                        deadline: block.timestamp,
                        amountIn: amount,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    })
                );
                usdtReceived = 0;
            } else if (_isTokenMigratedToDex(_token)) {
                _approve(_token, PANCAKE_ROUTER, amount);
                address[] memory path = new address[](2);
                path[0] = _token;
                path[1] = USDT;
                IPancakeRouter(PANCAKE_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    amount,
                    0,
                    path,
                    msg.sender,
                    block.timestamp
                );
                usdtReceived = 0; // 已直接转给 msg.sender，不在此返回数量
            } else {
                _approve(_token, PORTAL, amount);
                ExactInputParams memory params = ExactInputParams({
                    inputToken: _token,
                    outputToken: USDT,
                    inputAmount: amount,
                    minOutputAmount: 0,
                    permitData: bytes("")
                });
                usdtReceived = IPortal(PORTAL).swapExactInput{value: 0}(params);
                TransferHelper.safeTransfer(USDT, msg.sender, usdtReceived);
            }
        }
    }
