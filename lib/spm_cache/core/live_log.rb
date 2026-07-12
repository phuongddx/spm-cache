# frozen_string_literal: true

require "tty-cursor"
require "tty-screen"

module SPMCache
  module Core
    class LiveLog
      attr_reader :sticky_lines, :captured

      def initialize
        @cursor = TTY::Cursor
        @sticky_lines = []
        @captured = []
        @sticky_count = 0
      end

      def sticky_section(title)
        line_index = @sticky_lines.size
        @sticky_lines << title
        render_sticky(line_index, title)
        @sticky_count = @sticky_lines.size
        yield if block_given?
      end

      def output(line)
        @captured << line
        move_to_sticky_area
        print line
      end

      def finish
        print @cursor.reset
      end

      def capture(&block)
        yield
      end

      private

      def render_sticky(index, text)
        print @cursor.column(1)
        print text
        print "\n" if index < @sticky_lines.size - 1
      end

      def move_to_sticky_area
        return if @sticky_count.zero?

        print @cursor.up(@sticky_count + 1)
        print @cursor.column(1)
      end
    end
  end
end
