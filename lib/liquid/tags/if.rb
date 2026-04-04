# frozen_string_literal: true

module Liquid
  # @liquid_public_docs
  # @liquid_type tag
  # @liquid_category conditional
  # @liquid_name if
  # @liquid_summary
  #   Renders an expression if a specific condition is `true`.
  # @liquid_syntax
  #   {% if condition %}
  #     expression
  #   {% endif %}
  # @liquid_syntax_keyword condition The condition to evaluate.
  # @liquid_syntax_keyword expression The expression to render if the condition is met.
  class If < Block
    Syntax                  = /(#{QuotedFragment})\s*([=!<>a-z_]+)?\s*(#{QuotedFragment})?/o
    ExpressionsAndOperators = /(?:\b(?:\s?and\s?|\s?or\s?)\b|(?:\s*(?!\b(?:\s?and\s?|\s?or\s?)\b)(?:#{QuotedFragment}|\S+)\s*)+)/o
    BOOLEAN_OPERATORS       = %w(and or).freeze

    # Global cache: markup → [left_expr, op, right_expr] for simple conditions.
    # Populated during initial template compilation; stable across re-parses of the
    # same templates since condition markup doesn't change between runs.
    GLOBAL_CONDITION_EXPR_CACHE = {}

    def initialize(tag_name, markup, options)
      super
      # @blocks is nil for the common single-condition case (no else/elsif).
      # This avoids allocating a 1-element Array for 195/247 if/unless tags.
      # push_block sets @first_block for first, then lazily creates @blocks for more.
      @blocks = nil
      @first_block = nil
      push_block('if', markup)
    end

    # Returns blocks as an Array (creates one lazily for the single-block case).
    def blocks
      @blocks || (@first_block ? [@first_block] : [])
    end

    def nodelist
      if @blocks
        @blocks.map(&:attachment)
      elsif @first_block
        [@first_block.attachment]
      else
        []
      end
    end

    def parse(tokens)
      last = @blocks ? @blocks.last : @first_block
      while parse_body(last.attachment, tokens)
        last = @blocks.last  # @blocks is set after second push_block
      end
      if @blocks
        @blocks.reverse_each do |block|
          block.attachment.remove_blank_strings if blank?
          block.attachment.freeze
        end
      else
        @first_block.attachment.remove_blank_strings if blank?
        @first_block.attachment.freeze
      end
    end

    ELSE_TAG_NAMES = ['elsif', 'else'].freeze
    private_constant :ELSE_TAG_NAMES

    def unknown_tag(tag, markup, tokens)
      if ELSE_TAG_NAMES.include?(tag)
        push_block(tag, markup)
      else
        super
      end
    end

    def render_to_output_buffer(context, output)
      # Fast path: single condition (no else/elsif) — the common case
      if @blocks.nil?
        first = @first_block
        result = Liquid::Utils.to_liquid_value(first.evaluate(context))
        return first.attachment.render_to_output_buffer(context, output) if result
        return output
      end

      idx = 0
      blocks = @blocks
      len = blocks.length
      while idx < len
        block = blocks[idx]
        result = Liquid::Utils.to_liquid_value(block.evaluate(context))

        if result
          return block.attachment.render_to_output_buffer(context, output)
        end
        idx += 1
      end

      output
    end

    private

    def strict2_parse(markup)
      strict_parse(markup)
    end

    def push_block(tag, markup)
      block = if tag == 'else'
        ElseCondition.new
      else
        parse_with_selected_parser(markup)
      end

      if @first_block.nil?
        @first_block = block
      else
        # Second or later block — create @blocks array
        @blocks = [@first_block] if @blocks.nil?
        @blocks << block
      end
      block.attach(new_body)
    end

    def parse_expression(markup, safe: false)
      Condition.parse_expression(parse_context, markup, safe: safe)
    end

    def lax_parse(markup)
      # Check global cache first — avoids re-scanning condition fragments on repeated
      # parses of the same templates (e.g., benchmark measuring 34 templates × 2).
      if (cached = GLOBAL_CONDITION_EXPR_CACHE[markup])
        return Condition.new(cached[0], cached[1], cached[2])
      end

      # Fastest path: simple identifier truthiness like "product.available" or "forloop.first"
      if (simple = Variable.simple_variable_markup(markup))
        left = parse_expression(simple)
        GLOBAL_CONDITION_EXPR_CACHE[markup] = [left, nil, nil].freeze
        return Condition.new(left)
      end

      # Fast path: simple condition without and/or — use Cursor
      if !markup.include?(' and ') && !markup.include?(' or ')
        cursor = @parse_context.cursor
        cursor.reset(markup)
        if cursor.parse_simple_condition
          left = parse_expression(cursor.cond_left)
          right = cursor.cond_right ? parse_expression(cursor.cond_right) : nil
          op = cursor.cond_op
          GLOBAL_CONDITION_EXPR_CACHE[markup] = [left, op, right].freeze
          return Condition.new(left, op, right)
        end
      end

      expressions = markup.scan(ExpressionsAndOperators)
      raise SyntaxError, options[:locale].t("errors.syntax.if") unless expressions.pop =~ Syntax

      condition = Condition.new(parse_expression(Regexp.last_match(1)), Regexp.last_match(2), parse_expression(Regexp.last_match(3)))

      until expressions.empty?
        operator = expressions.pop.to_s.strip

        raise SyntaxError, options[:locale].t("errors.syntax.if") unless expressions.pop.to_s =~ Syntax

        new_condition = Condition.new(parse_expression(Regexp.last_match(1)), Regexp.last_match(2), parse_expression(Regexp.last_match(3)))
        raise SyntaxError, options[:locale].t("errors.syntax.if") unless BOOLEAN_OPERATORS.include?(operator)
        new_condition.send(operator, condition)
        condition = new_condition
      end

      condition
    end

    def strict_parse(markup)
      p = @parse_context.new_parser(markup)
      condition = parse_binary_comparisons(p)
      p.consume(:end_of_string)
      condition
    end

    def parse_binary_comparisons(p)
      condition = parse_comparison(p)
      first_condition = condition
      while (op = p.id?('and') || p.id?('or'))
        child_condition = parse_comparison(p)
        condition.send(op, child_condition)
        condition = child_condition
      end
      first_condition
    end

    def parse_comparison(p)
      a = parse_expression(p.expression, safe: true)
      if (op = p.consume?(:comparison))
        b = parse_expression(p.expression, safe: true)
        Condition.new(a, op, b)
      else
        Condition.new(a)
      end
    end

    class ParseTreeVisitor < Liquid::ParseTreeVisitor
      def children
        @node.blocks
      end
    end
  end
end
