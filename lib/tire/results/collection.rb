module Tire
  module Results

    class Collection
      include Enumerable
      include Pagination

      attr_reader :time, :total, :options, :facets

      def initialize(response, options={})
        @response = response
        @options  = options
        @time     = response['took'].to_i
        @total    = response['hits']['total'].to_i
        @facets   = response['facets']
        @wrapper  = options[:wrapper] || Configuration.wrapper
      end

      def results
        @results ||= begin
          hits = @response['hits']['hits'].map { |d| d.update '_type' => Utils.unescape(d['_type']) }

          unless @options[:load]
            if @wrapper == Hash
              hits
            else
              hits.map do |h|
                 document = {}

                 # Update the document with content and ID
                 document = h['_source'] ? document.update( h['_source'] || {} ) : document.update( __parse_fields__(h['fields']) )
                 document.update( {'id' => h['_id']} )

                 # Update the document with meta information
                 ['_score', '_type', '_index', '_version', 'sort', 'highlight', '_explanation'].each { |key| document.update( {key => h[key]} || {} ) }

                 # Return an instance of the "wrapper" class
                 @wrapper.new(document)
              end
            end

          else
            return [] if hits.empty?

            records = {}
            @response['hits']['hits'].group_by { |item| item['_type'] }.each do |type, items|
              raise NoMethodError, "You have tried to eager load the model instances, " +
                                   "but Tire cannot find the model class because " +
                                   "document has no _type property." unless type

              begin
                klass = type.camelize.constantize
              rescue NameError => e
                raise NameError, "You have tried to eager load the model instances, but " +
                                 "Tire cannot find the model class '#{type.camelize}' " +
                                 "based on _type '#{type}'.", e.backtrace
              end
              ids = items.map { |h| h['_id'] }
              rel = klass.where(:id => ids)
              rel = @options[:load] === true ? rel.all : rel.all(@options[:load])
              map = records[type] = {}
              rel.each { |model| map[model.id.to_s] = model }
            end

            # Match up results with models, filtering out missing
            @missing  = []
            results = @response['hits']['hits'].map do |item|
              id, type = item['_id'], item['_type']
              model = records[type][id.to_s]
              @missing << { :id => id, :type => type, :class => klass } if model.nil?
              model
            end
            results.compact!
            results
          end
        end
      end

      def missing
        results
        @missing
      end

      def each(&block)
        results.each(&block)
      end

      def empty?
        results.empty?
      end

      def size
        results.size
      end
      alias :length :size

      def [](index)
        results[index]
      end

      def to_ary
        self
      end

      # Handles _source prefixed fields properly: strips the prefix and converts fields to nested Hashes
      #
      def __parse_fields__(fields={})
        ( fields ||= {} ).clone.each_pair do |key,value|
          next unless key.to_s =~ /_source/                 # Skip regular JSON immediately

          keys = key.to_s.split('.').reject { |n| n == '_source' }
          fields.delete(key)

          result = {}
          path = []

          keys.each do |name|
            path << name
            eval "result[:#{path.join('][:')}] ||= {}"
            eval "result[:#{path.join('][:')}] = #{value.inspect}" if keys.last == name
          end
          fields.update result
        end
        fields
      end

    end

  end
end
