require 'thread'
require 'functional'
require 'concurrent/smart_mutex'

behavior_info(:sync_event_demux,
              start: 0,
              stop: 0,
              accept: 0,
              respond: 1)

behavior_info(:async_event_demux,
              start: 0,
              stop: 0,
              set_reactor: 1)

behavior_info(:demux_reactor,
              handle: -2)

module Concurrent

  class Reactor

    behavior(:demux_reactor)

    RESERVED_EVENTS = [ :stop ]

    EventContext = Struct.new(:event, :args, :callback)

    def initialize(demux = nil)
      @demux = demux
      if @demux.nil? || @demux.behaves_as?(:async_event_demux)
        @sync = false
        @queue = Queue.new
        @demux.set_reactor(self) unless @demux.nil?
      elsif @demux.behaves_as?(:sync_event_demux)
        @sync = true
      else
        raise ArgumentError.new("invalid event demultiplexer '#{@demux}'")
      end

      #unless demux.nil? || demux.behaves_as?(:sync_event_demux)
        #raise ArgumentError.new('invalid event demultiplexer')
      #end

      #@demux = demux
      #@demux.set_reactor(self) unless @demux.nil?

      @running = false
      #@queue = Queue.new
      @handlers = Hash.new
      @mutex = SmartMutex.new
    end

    def add_handler(event, &block)
      event = event.to_sym
      raise ArgumentError.new("'#{event}' is a reserved event") if RESERVED_EVENTS.include?(event)
      raise ArgumentError.new('no block given') unless block_given?
      @mutex.synchronize {
        @handlers[event] = block
      }
      return true
    end

    def remove_handler(event)
      handler = @mutex.synchronize {
        @handlers.delete(event.to_sym)
      }
      return ! handler.nil?
    end

    def stop_on_signal(*signals)
      signals.each{|signal| Signal.trap(signal){ self.stop } }
    end

    def handle_event(event, *args)
      raise NotImplementedError.new("demultiplexer '#{@demux.class}' is synchronous") if @sync 
      return [:stopped, 'reactor not running'] unless running?
      context = EventContext.new(event.to_sym, args.dup, Queue.new)
      @queue.push(context)
      return context.callback.pop
    end
    alias_method :handle, :handle_event

    def running?
      return @running
    end

    def start
      raise StandardError.new('already running') if self.running?
      @sync ? (@running = true; run_sync) : (@running = true; run_async)
    end

    def stop
      return unless self.running?
      @queue.push(:stop)
      return nil
    end

    private

    def run_sync
      @demux.start
      loop do
        context = @demux.accept

        #break if context == :stop
        #handler = @mutex.synchronize {
          #@handlers[context.event]
        #}






        @demux.respond('Hello World!')
      end
      atomic {
        @running = false
        @demux.stop unless @demux.nil?
      }
    end

    def run_async
      @demux.start unless @demux.nil?
      loop do
        context = @queue.pop
        break if context == :stop
        handler = @mutex.synchronize {
          @handlers[context.event]
        }
        if handler.nil?
          context.callback.push([:noop, "'#{context.event}' handler not found"])
        else
          begin
            result = handler.call(*context.args)
            context.callback.push([:ok, result])
          rescue Exception => ex
            context.callback.push([:ex, ex])
          end
        end
      end
      atomic {
        @running = false
        @demux.stop unless @demux.nil?
      }
    end
  end
end