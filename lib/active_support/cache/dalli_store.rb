begin
  require 'dalli'
rescue LoadError => e
  $stderr.puts "You don't have dalli installed in your application. Please add it to your Gemfile and run bundle install"
  raise e
end
require 'digest/md5'

module ActiveSupport
  module Cache
    # A cache store implementation which stores data in Memcached:
    # http://www.danga.com/memcached/
    #
    # DalliStore implements the Strategy::LocalCache strategy which implements
    # an in memory cache inside of a block.
    class DalliStore < Store
      module Response # :nodoc:
        STORED      = "STORED\r\n"
        NOT_STORED  = "NOT_STORED\r\n"
        EXISTS      = "EXISTS\r\n"
        NOT_FOUND   = "NOT_FOUND\r\n"
        DELETED     = "DELETED\r\n"
      end

      ESCAPE_KEY_CHARS = /[\x00-\x20%\x7F-\xFF]/

      def self.build_mem_cache(*addresses)
        addresses = addresses.flatten
        options = addresses.extract_options!
        addresses = ["localhost:11211"] if addresses.empty?
        Dalli::Client.new(addresses, options)
      end

      # Creates a new DalliStore object, with the given memcached server
      # addresses. Each address is either a host name, or a host-with-port string
      # in the form of "host_name:port". For example:
      #
      #   ActiveSupport::Cache::DalliStore.new("localhost", "server-downstairs.localnetwork:8229")
      #
      # If no addresses are specified, then DalliStore will connect to
      # localhost port 11211 (the default memcached port).
      #
      def initialize(*addresses)
        addresses = addresses.flatten
        options = addresses.extract_options!
        super(options)

        if addresses.first.respond_to?(:get)
          @data = addresses.first
        else
          mem_cache_options = options.dup
          UNIVERSAL_OPTIONS.each{|name| mem_cache_options.delete(name)}
          @data = self.class.build_mem_cache(*(addresses + [mem_cache_options]))
        end

        extend Strategy::LocalCache
        extend LocalCacheWithRaw
      end

      # Reads multiple keys from the cache using a single call to the
      # servers for all keys. Options can be passed in the last argument.
      def read_multi(*names)
        options = names.extract_options!
        options = merged_options(options)
        keys_to_names = names.inject({}){|map, name| map[escape_key(namespaced_key(name, options))] = name; map}
        raw_values = @data.get_multi(keys_to_names.keys)
        values = {}
        raw_values.each do |key, value|
          entry = deserialize_entry(value)
          values[keys_to_names[key]] = entry.value unless entry.expired?
        end
        values
      end

      # Increment a cached value. This method uses the memcached incr atomic
      # operator and can only be used on values written with the :raw option.
      # Calling it on a value not stored with :raw will initialize that value
      # to zero.
      def increment(name, amount = 1, options = nil) # :nodoc:
        options = merged_options(options)
        response = instrument(:increment, name, :amount => amount) do
          @data.incr(escape_key(namespaced_key(name, options)), amount)
        end
        response == Response::NOT_FOUND ? nil : response.to_i
      rescue Dalli::DalliError
        nil
      end

      # Decrement a cached value. This method uses the memcached decr atomic
      # operator and can only be used on values written with the :raw option.
      # Calling it on a value not stored with :raw will initialize that value
      # to zero.
      def decrement(name, amount = 1, options = nil) # :nodoc:
        options = merged_options(options)
        response = instrument(:decrement, name, :amount => amount) do
          @data.decr(escape_key(namespaced_key(name, options)), amount)
        end
        response == Response::NOT_FOUND ? nil : response.to_i
      rescue Dalli::DalliError
        nil
      end

      # Clear the entire cache on all memcached servers. This method should
      # be used with care when using a shared cache.
      def clear(options = nil)
        @data.flush_all
      end

      # Get the statistics from the memcached servers.
      def stats
        @data.stats
      end

      protected
        # Read an entry from the cache.
        def read_entry(key, options) # :nodoc:
          deserialize_entry(@data.get(escape_key(key)))
        rescue Dalli::DalliError => e
          logger.error("DalliError (#{e}): #{e.message}") if logger
          nil
        end

        # Write an entry to the cache.
        def write_entry(key, entry, options) # :nodoc:
          method = options && options[:unless_exist] ? :add : :set
          value = options[:raw] ? entry.value.to_s : entry
          expires_in = options[:expires_in].to_i
          if expires_in > 0 && !options[:raw]
            # Set the memcache expire a few minutes in the future to support race condition ttls on read
            expires_in += 5.minutes
          end
          @data.send(method, escape_key(key), value, expires_in)
        rescue Dalli::DalliError => e
          logger.error("DalliError (#{e}): #{e.message}") if logger
          false
        end

        # Delete an entry from the cache.
        def delete_entry(key, options) # :nodoc:
          @data.delete(escape_key(key))
        rescue Dalli::DalliError => e
          logger.error("DalliError (#{e}): #{e.message}") if logger
          false
        end

      private
        def escape_key(key)
          key = key.to_s.gsub(ESCAPE_KEY_CHARS){|match| "%#{match.getbyte(0).to_s(16).upcase}"}
          key = "#{key[0, 213]}:md5:#{Digest::MD5.hexdigest(key)}" if key.size > 250
          key
        end

        def deserialize_entry(raw_value)
          if raw_value
            entry = Marshal.load(raw_value) rescue raw_value
            entry.is_a?(Entry) ? entry : Entry.new(entry)
          else
            nil
          end
        end

      # Provide support for raw values in the local cache strategy.
      module LocalCacheWithRaw # :nodoc:
        protected
          def write_entry(key, entry, options) # :nodoc:
            retval = super
            if options[:raw] && local_cache && retval
              raw_entry = Entry.new(entry.value.to_s)
              raw_entry.expires_at = entry.expires_at
              local_cache.write_entry(key, raw_entry, options)
            end
            retval
          end
      end
    end
  end
end
