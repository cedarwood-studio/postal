# frozen_string_literal: true

require "rails_helper"

describe Credential do
  # The options column holds a Hash serialized as YAML text. These examples pin
  # the text as Rails 7.1.6 writes it and check that rows holding that text can
  # still be read.
  describe "#options" do
    let(:credential) { create(:credential) }

    def stored_options
      credential.reload.read_attribute_before_type_cast(:options)
    end

    def store_options(text)
      connection = described_class.connection
      connection.update("UPDATE credentials SET options = #{connection.quote(text)} WHERE id = #{credential.id}")
    end

    it "is an empty hash for a new credential and stores NULL" do
      expect(credential.options).to eq({})
      expect(stored_options).to be_nil
    end

    it "stores a hash with string keys as YAML" do
      credential.update!(options: { "a" => "b", "n" => 1 })
      expect(stored_options).to eq %(---\na: b\n"n": 1\n)
    end

    it "stores a hash with symbol keys as YAML" do
      credential.update!(options: { a: "b", list: ["x", 2], nested: { t: true } })
      expect(stored_options).to eq "---\n:a: b\n:list:\n- x\n- 2\n:nested:\n  :t: true\n"
    end

    it "reads a stored YAML hash with string keys" do
      store_options(%(---\na: b\n"n": 1\n))
      expect(credential.reload.options).to eq({ "a" => "b", "n" => 1 })
    end

    it "reads a stored YAML hash with symbol keys" do
      store_options("---\n:a: b\n:list:\n- x\n- 2\n:nested:\n  :t: true\n")
      expect(credential.reload.options).to eq({ a: "b", list: ["x", 2], nested: { t: true } })
    end

    it "reads a stored NULL as an empty hash" do
      store_options(nil)
      expect(credential.reload.options).to eq({})
    end
  end
end
