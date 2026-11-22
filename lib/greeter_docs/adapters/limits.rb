# frozen_string_literal: true

require 'yaml'

module GreeterDocs
  module Adapters
    # Input limits shared by the file and network sources (design S4).
    module Limits
      MAX_BYTES = 5 * 1024 * 1024

      module_function

      # Reads a file of at most MAX_BYTES, or raises SourceError naming label.
      def read(path, label)
        raise SourceError, "#{label}: not found" unless File.file?(path)
        raise SourceError, "#{label}: larger than 5 MiB" if File.size(path) > MAX_BYTES

        File.binread(path)
      end

      # Plain YAML data only: no aliases, tags or object loading.
      def yaml(text, label)
        YAML.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: false)
      rescue Psych::Exception => e
        raise SourceError, "#{label}: not plain YAML data (#{e.class.name.split('::').last})"
      end
    end
  end
end
