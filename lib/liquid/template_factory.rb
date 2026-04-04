# frozen_string_literal: true

module Liquid
  class TemplateFactory
    # Singleton default instance — stateless, safe to share across all renders
    DEFAULT = new.freeze

    def for(_template_name)
      Liquid::Template.new
    end
  end
end
