module TokenAdapter
    class Erc20 < Eth

      # required: token_contract_address, token_decimals
      # optional: transfer_gas_limit, transfer_gas_price
      def initialize(config = {})
        super(config)
      end

      # required: address
      def getbalance(options = {})
        function_signature = '70a08231' # Ethereum::Function.calc_id('balanceOf(address)') # 70a08231
        data = '0x' + function_signature + padding(options[:address])
        to = config[:token_contract_address]

        BigDecimal[eth_call(to, data).to_i(16)] / BigDecimal[10**config[:token_decimals]]
      end

      # required: priv, address, amount
      # optional: gas_limit, gas_price
      def sendtoaddress(options = {})
        priv = options[:priv]
        address = options[:address]
        amount  = options[:amount]
        gas_limit = options[:gas_limit] || config[:transfer_gas_limit] || TokenAdapter::Eth.transfer_gas_limit
        gas_price = options[:gas_price] || config[:transfer_gas_price] || TokenAdapter::Eth.transfer_gas_price
        to = config[:token_contract_address]
        data = build_data(address, amount) 

        txhash = send_raw_transaction(priv, 0, data, gas_limit, gas_price, to)
        raise TxHashError, 'txhash is nil' unless txhash
        txhash
      end

      # 用于充值，严格判断
      def gettransaction(options = {})
        txid = options[:txid]
        tx = super(options)
        return nil unless tx

        # 数量 和 地址
        data = tx['input'] || tx['raw']
        input = extract_input(data)
        from = '0x' + padding(tx['from'])
        to = '0x' + input[:params][0]
        value = '0x' + input[:params][1]

        # 看看这个交易实际有没有成功
        return nil unless has_transfer_event_log?(tx['receipt'], from, to, value)

        # 填充交易所需要的数据
        tx['details'] = [
          {
            'account' => 'payment',
            'category' => 'receive',
            'amount' => value.to_i(16) / 10.0**token_decimals,
            'address' => "0x#{input[:params][0][24 .. input[:params][0].length-1]}"
          }
        ]

        return tx
      end

      private
      def build_data(address, amount)
        function_signature = 'a9059cbb' # Ethereum::Function.calc_id('transfer(address,uint256)') # a9059cbb
        amount_in_wei = (amount * (10**token_decimals)).to_i
        '0x' + function_signature + padding(address) + padding(dec_to_hex(amount_in_wei))
      end

    end
  end

end
