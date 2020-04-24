# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

# The StreamingBuffer class provides an Enumerator to the standard Ruby Queue
# class.  The enumerator is blocking while the queue is empty.
module NewRelic::Agent
  module InfiniteTracing
    class StreamingBuffer
      include Enumerable
      extend Forwardable
      def_delegators :@queue, :empty?, :num_waiting
      
      SPANS_SEEN_METRIC   = "Supportability/InfiniteTracing/Span/Seen"
      SPANS_SENT_METRIC   = "Supportability/InfiniteTracing/Span/Sent"
      QUEUE_DUMPED_METRIC = "Supportability/InfiniteTracing/Span/AgentQueueDumped"

      DEFAULT_QUEUE_SIZE = 10_000
      FLUSH_DELAY = 0.005

      attr_reader :queue

      def initialize max_size = DEFAULT_QUEUE_SIZE
        @max_size = max_size
        @mutex = Mutex.new
        @queue = Queue.new
      end

      # Dumps the contents of this streaming buffer onto 
      # the given buffer and closes the queue
      def transfer new_buffer
        @mutex.synchronize do
          until @queue.empty? do new_buffer.push @queue.pop end
          @queue.close
        end
      end

      # Pushes the segment given onto the queue.
      #
      # If the queue is at capacity, it is dumped and a
      # supportability metric is recorded for the event.
      #
      # When a restart signal is received, the queue is
      # locked with a mutex, blocking the push until
      # the queue has restarted.
      def << segment
        @mutex.synchronize do
          clear_queue if @queue.size >= @max_size
          NewRelic::Agent.increment_metric SPANS_SEEN_METRIC
          @queue.push segment
        end
      end

      # Drops all segments from the queue and records a
      # supportability metric for the event.
      def clear_queue
        @queue.clear
        NewRelic::Agent.increment_metric QUEUE_DUMPED_METRIC
      end

      # Waits for the queue to be fully consumed or for the
      # waiting consumers to release.
      def flush_queue
        @queue.num_waiting.times { @queue.push nil }
        close_queue
        until @queue.empty? do sleep(FLUSH_DELAY) end
      end

      def close_queue
        @mutex.synchronize { @queue.close }
      end

      # Returns the blocking enumerator that will pop
      # items off the queue while any items are present
      # If +nil+ is popped, the queue is closing.
      #
      # The segment is transformed into a serializable 
      # span here so processing is taking place within
      # the gRPC call's thread rather than in the main 
      # application thread.
      def enumerator
        return enum_for(:enumerator) unless block_given?
        loop do
          if segment = @queue.pop(false)
            NewRelic::Agent.increment_metric SPANS_SENT_METRIC
            yield transform(segment)

          else
            raise ClosedQueueError
          end
        end
      end

      private

      def transform segment
        span_event = SpanEventPrimitive.for_segment segment
        Span.new Transformer.transform(span_event)
      end

    end
  end
end
