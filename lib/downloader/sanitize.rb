# frozen_string_literal: true

require "cgi"

# --- Sanitize shim (fragment only) ---
# Minimal Sanitize module implementation for text extraction from HTML
# Only provides fragment method for stripping tags and normalizing text
unless defined?(Sanitize)
  module Sanitize
    module_function

    WHITESPACE = /\s+/.freeze
    SCRIPT_CLOSE = "</script"
    STYLE_CLOSE = "</style"
    COMMENT_CLOSE = "-->"

    def fragment(html)
      return "" if html.nil?
      input = html.to_s
      return "" if input.empty?

      fallback_fragment(input)
    end

    def fallback_fragment(input)
      result = +""
      lower = input.downcase
      index = 0
      skip_until = nil

      while index < input.length
        if skip_until
          closing = lower.index(skip_until, index)
          break unless closing
          close_gt = input.index(">", closing + skip_until.length)
          index = close_gt ? close_gt + 1 : closing + skip_until.length
          skip_until = nil
          next
        end

        if input.getbyte(index) == 60 # "<"
          if lower[index, 4] == "<!--"
            closing = lower.index(COMMENT_CLOSE, index + 4)
            break unless closing
            index = closing + COMMENT_CLOSE.length
            next
          end

          close = input.index(">", index + 1)
          break unless close
          tag = lower[(index + 1)...close].lstrip
          tag_name = extract_tag_name(tag)
          skip_until =
            case tag_name
            when "script"
              SCRIPT_CLOSE
            when "style"
              STYLE_CLOSE
            end
          index = close + 1
          next
        end

        result << input[index]
        index += 1
      end

      normalize_text(result)
    end
    private_class_method :fallback_fragment

    def extract_tag_name(tag)
      idx = 0
      len = tag.length
      while idx < len
        byte = tag.getbyte(idx)
        if byte == 47 || byte <= 32 # '/' or whitespace
          idx += 1
          next
        elsif byte >= 97 && byte <= 122 # a-z
          start = idx
          idx += 1
          while idx < len
            b = tag.getbyte(idx)
            break unless (b >= 97 && b <= 122) || (b >= 48 && b <= 57) || b == 45
            idx += 1
          end
          return tag.slice(start, idx - start)
        else
          break
        end
      end
      nil
    end
    private_class_method :extract_tag_name

    def normalize_text(text)
      buffer = text.to_s
      buffer.gsub!(/&nbsp;|&#160;/i, " ")
      unescaped = ::CGI.unescapeHTML(buffer)
      unescaped.tr!("\u00A0", " ")
      unescaped.gsub!(WHITESPACE, " ")
      unescaped.strip
    end
    private_class_method :normalize_text
  end
end
# --- /Sanitize shim ---
