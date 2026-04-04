# frozen_string_literal: true

require_relative 'if'

module Liquid
  # @liquid_public_docs
  # @liquid_type tag
  # @liquid_category conditional
  # @liquid_name unless
  # @liquid_summary
  #   Renders an expression unless a specific condition is `true`.
  # @liquid_description
  #   > Tip:
  #   > Similar to the [`if` tag](/docs/api/liquid/tags/if), you can use `elsif` to add more conditions to an `unless` tag.
  # @liquid_syntax
  #   {% unless condition %}
  #     expression
  #   {% endunless %}
  # @liquid_syntax_keyword condition The condition to evaluate.
  # @liquid_syntax_keyword expression The expression to render unless the condition is met.
  class Unless < If
    def render_to_output_buffer(context, output)
      # First condition is interpreted backwards ( if not )
      # @first_block is always set; @blocks is nil for single-condition unless
      first_block = @first_block
      result = Liquid::Utils.to_liquid_value(
        first_block.evaluate(context),
      )

      unless result
        return first_block.attachment.render_to_output_buffer(context, output)
      end

      # After the first condition unless works just like if (check else/elsif)
      if @blocks
        idx = 1  # skip first block (already handled above)
        blocks = @blocks
        len = blocks.length
        while idx < len
          block = blocks[idx]
          result = Liquid::Utils.to_liquid_value(block.evaluate(context))
          return block.attachment.render_to_output_buffer(context, output) if result
          idx += 1
        end
      end

      output
    end
  end
end
