# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "rails/generators"
require "tmpdir"
require "generators/parade_db/index/index_generator"

RSpec.describe ParadeDB::Generators::IndexGenerator do
  let(:destination) { File.join(Dir.tmpdir, "parade_db_generator_test_#{Process.pid}") }

  def run_generator(args, generator_options = {})
    generator = described_class.new(
      args,
      generator_options,
      destination_root: destination
    )
    silence_stream($stdout) { generator.invoke_all }
    generator
  end

  def silence_stream(stream)
    old = stream.dup
    stream.reopen(File::NULL)
    yield
  ensure
    stream.reopen(old)
    old.close
  end

  def generated_index_path(model)
    File.join(destination, "app/parade_db/#{model.underscore}_index.rb")
  end

  def generated_migration_path(model)
    Dir.glob(File.join(destination, "db/migrate/*_create_#{model.underscore.pluralize}_bm25_index.rb")).first
  end

  before { FileUtils.mkdir_p(destination) }
  after  { FileUtils.rm_rf(destination) }

  describe "index class" do
    it "generates the file at app/parade_db/<model>_index.rb" do
      run_generator(["Product"])
      expect(File.exist?(generated_index_path("Product"))).to be true
    end

    it "defines the correct class name" do
      run_generator(["Product"])
      content = File.read(generated_index_path("Product"))
      expect(content).to include("class ProductIndex < ParadeDB::Index")
    end

    it "sets table_name and key_field" do
      run_generator(["Product"])
      content = File.read(generated_index_path("Product"))
      expect(content).to include("self.table_name = :products")
      expect(content).to include("self.key_field  = :id")
    end

    it "always includes the id field" do
      run_generator(["Product"])
      content = File.read(generated_index_path("Product"))
      expect(content).to include("id: {}")
    end

    it "includes extra fields passed as arguments" do
      run_generator(["Product", "description", "category", "rating"])
      content = File.read(generated_index_path("Product"))
      expect(content).to include("description: {}")
      expect(content).to include("category: {}")
      expect(content).to include("rating: {}")
    end

    it "handles multi-word model names" do
      run_generator(["LineItem"])
      content = File.read(generated_index_path("LineItem"))
      expect(content).to include("class LineItemIndex < ParadeDB::Index")
      expect(content).to include("self.table_name = :line_items")
    end
  end

  describe "migration" do
    it "generates a migration file" do
      run_generator(["Product"])
      expect(generated_migration_path("Product")).not_to be_nil
    end

    it "calls create_paradedb_index with the index class" do
      run_generator(["Product"])
      content = File.read(generated_migration_path("Product"))
      expect(content).to include("create_paradedb_index(ProductIndex, if_not_exists: true)")
    end

    it "calls remove_bm25_index in down" do
      run_generator(["Product"])
      content = File.read(generated_migration_path("Product"))
      expect(content).to include("remove_bm25_index :products, name: :products_bm25_idx, if_exists: true")
    end

    it "does not include disable_ddl_transaction! by default" do
      run_generator(["Product"])
      content = File.read(generated_migration_path("Product"))
      expect(content).not_to include("disable_ddl_transaction!")
    end

    context "with --concurrent" do
      it "adds disable_ddl_transaction! to the migration" do
        run_generator(["Product"], "concurrent" => true)
        content = File.read(generated_migration_path("Product"))
        expect(content).to include("disable_ddl_transaction!")
      end

      it "places disable_ddl_transaction! before the up method" do
        run_generator(["Product"], "concurrent" => true)
        content = File.read(generated_migration_path("Product"))
        expect(content.index("disable_ddl_transaction!")).to be < content.index("def up")
      end
    end

    it "handles multi-word model names in migration class" do
      run_generator(["LineItem"])
      content = File.read(generated_migration_path("LineItem"))
      expect(content).to include("class CreateLineItemBm25Index")
      expect(content).to include("remove_bm25_index :line_items")
    end
  end
end
