# frozen_string_literal: true

module ParadeDB
  module Diagnostics
    module_function

    def indexes(connection: ActiveRecord::Base.connection)
      execute_table_function(connection, "SELECT * FROM pdb.indexes()")
    end

    def index_segments(index, connection: ActiveRecord::Base.connection)
      sql = "SELECT * FROM pdb.index_segments(#{connection.quote(index.to_s)}::regclass)"
      execute_table_function(connection, sql)
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
