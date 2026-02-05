# frozen_string_literal: true

require_relative "relation"
require "active_support/concern"

module ParadeDB
  module Model
    extend ActiveSupport::Concern

    def self.included(base)
      base.extend(ClassMethods)
      base.class_attribute :has_parade_db_index, default: false
    end

    module ClassMethods
      def search(column)
        ensure_parade_ready!
        Relation.new(self).search(column)
      end

      def similar_to(key, fields: nil)
        ensure_parade_ready!
        Relation.new(self).similar_to(key, fields: fields)
      end

      def parade_arel
        @parade_arel ||= ParadeDB::Arel::Builder.new(table_name)
      end

      private

      def ensure_parade_ready!
        unless has_parade_db_index
          raise "ParadeDB is not enabled for #{name} (set self.has_parade_db_index = true)"
        end
      end
    end
  end
end
