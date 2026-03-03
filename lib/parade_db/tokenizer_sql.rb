# frozen_string_literal: true

module ParadeDB
  module TokenizerSQL
    module_function

    def qualify(tokenizer)
      value = tokenizer.to_s.strip
      return qualify_name(value) unless value.include?("(")

      function_name, rest = value.split("(", 2)
      "#{qualify_name(function_name)}(#{rest}"
    end

    def qualify_name(function_name)
      return function_name if function_name.include?(".") || function_name.include?("::")

      "pdb.#{function_name}"
    end
  end
end
