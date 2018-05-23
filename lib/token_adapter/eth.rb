module TokenAdapter
  class Eth < Base
    include TokenAdapter::Client::Ethereum

    class << self
      attr_accessor :rpc_url,
                    :transfer_gas_limit, :transfer_gas_price
    end

    attr_accessor :rpc

    # optional: transfer_gas_limit, transfer_gas_price
    def initialize(config = {})
      super(config)
      init_provider(config[:rpc_url] || TokenAdapter::Eth.rpc_url)
    end

    # 获取地址上的币
    # required: address
    def getbalance(options = {})
      result = eth_get_balance(options[:address])
      BigDecimal(result.to_i(16)) / BigDecimal(10**18)
    end

    # required: xpub, index
    def getnewaddress(options = {})
      xpub = options[:xpub]
      index = options[:index]
      wallet = Bip44::Wallet.from_xpub(xpub)
      wallet.get_ethereum_address("M/#{index}")
    end

    # required: address, amount
    # optional: priv, gas_limit, gas_price
    def sendtoaddress(options = {})
      priv = options[:priv] || config[:exchange_address_priv] || TokenAdapter::Eth.exchange_address_priv
      address = options[:address]
      amount  = options[:amount]
      gas_limit = options[:gas_limit] || config[:transfer_gas_limit] || TokenAdapter::Eth.transfer_gas_limit
      gas_price = options[:gas_price] || config[:transfer_gas_price] || TokenAdapter::Eth.transfer_gas_price

      txhash = send_raw_transaction(priv, amount, nil, gas_limit, gas_price, address)
      raise TokenAdapter::TxHashError, 'txhash is nil' unless txhash
      txhash
    end

    # 用于充值，自己添加的属性，数字是10进制的（原始的是字符串形式的16进制）
    # 严格判断
    # required: txid
    def gettransaction(options = {})
      txid = options[:txid]
      tx = eth_get_transaction_by_hash(txid)
      return nil unless (tx && tx['blockNumber']) # 未上链的直接返回nil，有没有可能之后又上链了？

      receipt = eth_get_transaction_receipt(tx['hash'])
      return nil unless receipt
      raise TokenAdapter::TransactionError, 'Transaction Fail' if (receipt['status'] && receipt['status'] == '0x0')
      # raise TokenAdapter::TransactionError, 'out of gas' if out_of_gas?(tx, receipt)

      # 把回执也作为tx的一部分返回
      tx['receipt'] = receipt

      # 确认数
      current_block_number = eth_block_number.to_i(16) # 当前的高度
      return nil unless current_block_number
      transaction_block_number = hex_to_dec(tx['blockNumber'])
      tx['confirmations'] = current_block_number - transaction_block_number

      # 上链时间
      block = eth_get_block_by_number(tx['blockNumber'])
      if block
        tx['timereceived'] = hex_to_dec(block['timestamp'])
      else
        tx['timereceived'] = Time.now.to_i
      end

      # 数量 和 地址
      tx['details'] = [
        {
          'account' => 'payment',
          'category' => 'receive',
          'amount' => hex_wei_to_dec_eth(tx['value']),
          'address' => tx['to']
        }
      ]

      return tx
    end

    # inner methods
    def generate_raw_transaction(private_key, value, data, gas_limit, gas_price = nil, to = nil, nonce = nil)
      key = ::Eth::Key.new priv: private_key
      address = key.address
    
      gas_price_in_dec = gas_price.nil? ? eth_gas_price.to_i(16) : gas_price
      nonce = nonce.nil? ? eth_get_transaction_count(address, 'pending').to_i(16) : nonce
  
      args = {
        from: address,
        value: 0,
        data: '0x0',
        nonce: nonce,
        gas_limit: gas_limit,
        gas_price: gas_price_in_dec
      }
  
      args[:value] = (value * 10**18).to_i if value
      args[:data] = data if data
      args[:to] = to if to
      tx = Eth::Tx.new(args)
      tx.sign key
      tx.hex
    end

    def send_raw_transaction(priv, value, data, gas_limit, gas_price, to = nil)
      rawtx = generate_raw_transaction(priv, value, data, gas_limit, gas_price, to)
      txhash = eth_send_raw_transaction(rawtx) if rawtx
      return txhash
    end

    # 工具
    def hex_wei_to_dec_eth(wei)
      hex_to_dec(wei)/10.0**18
    end

    def dec_eth_to_hex_wei(value)
      dec_wei = (value * 10**18).to_i
      dec_to_hex(dec_wei)
    end

    def dec_to_hex(value)
      '0x'+value.to_s(16)
    end

    def hex_to_dec(value)
      value.to_i(16)
    end
    
    def str_to_hex(s)
      '0x'+s.each_byte.map { |b| b.to_s(16) }.join
    end

    def padding(str)
      if str =~ /^0x[a-f0-9]*/
        str = str[2 .. str.length-1]
      end
      str.rjust(64, '0')
    end

    def without_0x(address)
      address[2 .. address.length-1]
    end

    def eth_address(str)
      str = str.to_s
      if str.size == 66
        new_addr = str[0,2] + str[26, str.size - 26]
      else
        new_addr = str
      end
      new_addr
    end
    
  end
end
