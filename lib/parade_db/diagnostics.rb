# frozen_string_literal: true

module ParadeDB
  module Diagnostics
    module_function

    def aggregate(index, query, spec, solve_mvcc: nil, memory_limit: 500000000, bucket_limit: nil, visibility: nil, connection: ActiveRecord::Base.connection)
      unless memory_limit.is_a?(Integer) && memory_limit.positive? && (bucket_limit.nil? || (bucket_limit.is_a?(Integer) && bucket_limit.positive?))
        raise ArgumentError, "memory_limit and bucket_limit must be positive integers"
      end
      if visibility && !%w[transaction raw threshold].include?(visibility)
        raise ArgumentError, "visibility must be transaction, raw, or threshold"
      end
      raise ArgumentError, "Specify solve_mvcc or visibility, not both" unless solve_mvcc.nil? || visibility.nil?
      input = query.is_a?(SearchQuery) ? query : SearchQuery.parse(query)
      args = ["#{connection.quote(index.to_s)}::regclass", input.to_sql(connection: connection), "#{connection.quote(JSON.generate(spec))}::json", connection.quote(solve_mvcc), memory_limit, bucket_limit || "NULL", connection.quote(visibility)]
      value = connection.select_value("SELECT paradedb.aggregate(#{args.join(', ')})")
      value.is_a?(String) ? JSON.parse(value) : value
    end

    def indexes(connection: ActiveRecord::Base.connection)
      execute_table_function(connection, "SELECT * FROM pdb.indexes()")
    end

    def index_segments(index, connection: ActiveRecord::Base.connection)
      sql = "SELECT * FROM pdb.index_segments(#{connection.quote(index.to_s)}::regclass)"
      execute_table_function(connection, sql)
    end

    def vector_info(index, field, connection: ActiveRecord::Base.connection)
      args = "#{connection.quote(index.to_s)}::regclass, #{connection.quote(field.to_s)}::text"
      execute_table_function(connection, "SELECT * FROM paradedb.vector_info(#{args})")
    end

    def vector_config(index, field, connection: ActiveRecord::Base.connection)
      args = "#{connection.quote(index.to_s)}::regclass, #{connection.quote(field.to_s)}::text"
      execute_table_function(connection, "SELECT * FROM paradedb.vector_config(#{args})")
    end

    def vector_estimator_info(index, field, queries: nil, connection: ActiveRecord::Base.connection)
      args = "#{connection.quote(index.to_s)}::regclass, #{connection.quote(field.to_s)}::text"
      unless queries.nil?
        vectors = queries.map { |query| connection.quote("[#{query.map { |value| Float(value) }.join(',')}]") }
        args += ", ARRAY[#{vectors.join(', ')}]::vector[]"
      end
      execute_table_function(connection, "SELECT * FROM paradedb.vector_estimator_info(#{args})")
    end

    def verify_index(
      index,
      heapallindexed: false,
      sample_rate: nil,
      report_progress: false,
      verbose: false,
      on_error_stop: false,
      segment_ids: nil,
      connection: ActiveRecord::Base.connection
    )
      sql = ["SELECT * FROM pdb.verify_index(#{connection.quote(index.to_s)}::regclass"]
      sql << ", heapallindexed => #{boolean_sql(heapallindexed)}" if heapallindexed
      sql << ", sample_rate => #{connection.quote(sample_rate)}::double precision" unless sample_rate.nil?
      sql << ", report_progress => #{boolean_sql(report_progress)}" if report_progress
      sql << ", verbose => #{boolean_sql(verbose)}" if verbose
      sql << ", on_error_stop => #{boolean_sql(on_error_stop)}" if on_error_stop
      unless segment_ids.nil?
        values = Array(segment_ids).map { |value| Integer(value) }
        sql << ", segment_ids => ARRAY[#{values.join(', ')}]::int[]"
      end
      sql << ")"

      execute_table_function(connection, sql.join)
    end

    def verify_all_indexes(
      schema_pattern: nil,
      index_pattern: nil,
      heapallindexed: false,
      sample_rate: nil,
      report_progress: false,
      on_error_stop: false,
      connection: ActiveRecord::Base.connection
    )
      params = []
      params << "schema_pattern => #{connection.quote(schema_pattern)}" unless schema_pattern.nil?
      params << "index_pattern => #{connection.quote(index_pattern)}" unless index_pattern.nil?
      params << "heapallindexed => #{boolean_sql(heapallindexed)}" if heapallindexed
      params << "sample_rate => #{connection.quote(sample_rate)}::double precision" unless sample_rate.nil?
      params << "report_progress => #{boolean_sql(report_progress)}" if report_progress
      params << "on_error_stop => #{boolean_sql(on_error_stop)}" if on_error_stop

      sql = if params.empty?
              "SELECT * FROM pdb.verify_all_indexes()"
            else
              "SELECT * FROM pdb.verify_all_indexes(#{params.join(', ')})"
            end

      execute_table_function(connection, sql)
    end

    def execute_table_function(connection, sql)
      result = connection.exec_query(sql)
      result.to_a
    end
    private_class_method :execute_table_function

    def boolean_sql(value)
      value ? "true" : "false"
    end
    private_class_method :boolean_sql
  end
end
