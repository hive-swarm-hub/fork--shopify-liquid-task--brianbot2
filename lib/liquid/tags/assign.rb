# frozen_string_literal: true

module Liquid
  # @liquid_public_docs
  # @liquid_type tag
  # @liquid_category variable
  # @liquid_name assign
  # @liquid_summary
  #   Creates a new variable.
  # @liquid_description
  #   You can create variables of any [basic type](/docs/api/liquid/basics#types), [object](/docs/api/liquid/objects), or object property.
  #
  #   > Caution:
  #   > Predefined Liquid objects can be overridden by variables with the same name.
  #   > To make sure that you can access all Liquid objects, make sure that your variable name doesn't match a predefined object's name.
  # @liquid_syntax
  #   {% assign variable_name = value %}
  # @liquid_syntax_keyword variable_name The name of the variable being created.
  # @liquid_syntax_keyword value The value you want to assign to the variable.
  class Assign < Tag
    Syntax = /(#{VariableSignature}+)\s*=\s*(.*)\s*/om

    # @api private
    def self.raise_syntax_error(parse_context)
      raise Liquid::SyntaxError, parse_context.locale.t('errors.syntax.assign')
    end

    attr_reader :to, :from

    # VariableSignature chars: [a-zA-Z0-9_\-\.\[\]\(\)]
    def self.var_sig_byte?(b)
      (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || (b >= 48 && b <= 57) ||
        b == 95 || b == 45 || b == 46 || b == 91 || b == 93 || b == 40 || b == 41
    end

    def initialize(tag_name, markup, parse_context)
      super
      # Byte-level parsing of "var_name = value_expr" — avoids MatchData allocation
      len = markup.bytesize
      pos = 0
      pos += 1 while pos < len && (markup.getbyte(pos) == 32 || markup.getbyte(pos) == 9 || markup.getbyte(pos) == 10 || markup.getbyte(pos) == 13)
      name_start = pos
      pos += 1 while pos < len && self.class.var_sig_byte?(markup.getbyte(pos))
      if pos > name_start
        name_end = pos
        pos += 1 while pos < len && (markup.getbyte(pos) == 32 || markup.getbyte(pos) == 9)
        if pos < len && markup.getbyte(pos) == 61 # '='
          pos += 1
          pos += 1 while pos < len && (markup.getbyte(pos) == 32 || markup.getbyte(pos) == 9)
          val_start = pos
          val_end = len
          val_end -= 1 while val_end > val_start && (markup.getbyte(val_end - 1) == 32 || markup.getbyte(val_end - 1) == 9 || markup.getbyte(val_end - 1) == 10 || markup.getbyte(val_end - 1) == 13)
          @to   = markup.byteslice(name_start, name_end - name_start)
          @from = Variable.new(val_end > val_start ? markup.byteslice(val_start, val_end - val_start) : "", parse_context)
          return
        end
      end
      self.class.raise_syntax_error(parse_context)
    end

    def render_to_output_buffer(context, output)
      val = @from.render(context)
      context.scopes.last[@to] = val
      context.resource_limits.increment_assign_score(assign_score_of(val))
      output
    end

    def blank?
      true
    end

    private

    def assign_score_of(val)
      if val.instance_of?(String)
        val.bytesize
      elsif val.instance_of?(Array)
        sum = 1
        # Uses #each to avoid extra allocations.
        val.each { |child| sum += assign_score_of(child) }
        sum
      elsif val.instance_of?(Hash)
        sum = 1
        val.each do |key, entry_value|
          sum += assign_score_of(key)
          sum += assign_score_of(entry_value)
        end
        sum
      else
        1
      end
    end

    class ParseTreeVisitor < Liquid::ParseTreeVisitor
      def children
        [@node.from]
      end
    end
  end
end
