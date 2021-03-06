class FFMPEG::FormatContext

  DTS_DELTA_THRESHOLD = 10

  MAX_AUDIO_PACKET_SIZE = 128 * 1024 # from ffmpeg.c, no clue why

  inline :C do |builder|
    FFMPEG.builder_defaults builder

    ##
    # FormatContext is responsible for freeing its codecs, codec_context and
    # streams.  The ruby object must hold a reference (instance variable) to
    # their parent object so FormatContext doesn't free memory GC.

    builder.prefix <<-C
      static void free_codecs(AVFormatContext * format_context)
      {
        int i;
        for(i = 0; i < format_context->nb_streams; i++) {
          if (format_context->streams[i]->codec->codec)
            avcodec_close(format_context->streams[i]->codec);
        }
      }

      static void free_streams(AVFormatContext * format_context)
      {
        int i;
        for(i = 0; i < format_context->nb_streams; i++) {
          av_free(format_context->streams[i]->codec);
          av_free(format_context->streams[i]);
        }
      }

      static void free_format_context(AVFormatContext *format_context) {
        if (format_context) {

          free_codecs(format_context);

          if (format_context->iformat) {
            av_close_input_file(format_context);
          } else {
            free_streams(format_context);
            av_free(format_context);
          }
        }
      }
    C

    ##
    # :singleton-method: allocate

    builder.c_singleton <<-C
      VALUE allocate() {
        AVFormatContext *format_context;

        format_context = avformat_alloc_context();

        VALUE obj = Data_Wrap_Struct(self, 0, free_format_context, format_context);

        return obj;
      }
    C

    ##
    # :method: filename=

    builder.c <<-C
      void filename_equals(VALUE _filename) {
        AVFormatContext *format_context;
        char * filename;

        filename = StringValueCStr(_filename);

        Data_Get_Struct(self, AVFormatContext, format_context);

        av_strlcpy(format_context->filename, filename, strlen(filename) + 1);
      }
    C

    ##
    # :method: input_format

    builder.c <<-C
      VALUE input_format() {
        VALUE format_klass;

        format_klass = rb_path2class("FFMPEG::InputFormat");

        return rb_funcall(format_klass, rb_intern("from"), 1, self);
      }
    C

    ##
    # :method: open

    builder.c <<-C, :method_name => :open
      VALUE oc_open(char *file_name, int flags) {
        AVFormatContext *format_context;
        int e;

        Data_Get_Struct(self, AVFormatContext, format_context);

        e = url_fopen(&format_context->pb, file_name, flags);

        ffmpeg_check_error(e);

        return self;
      }
    C

    ##
    # :method: open_input_file

    builder.c <<-C
      VALUE open_input_file(char *filename, VALUE _input_format, int buf_size,
                            VALUE _format_parameters) {
        AVFormatContext *format_context;
        AVInputFormat *input_format = NULL;
        AVFormatParameters *format_parameters = NULL;
        int e;

        Data_Get_Struct(self, AVFormatContext, format_context);

        if (RTEST(_input_format)) {
          Data_Get_Struct(_input_format, AVInputFormat, input_format);
        }

        if (RTEST(_format_parameters)) {
          Data_Get_Struct(_format_parameters, AVFormatParameters,
                          format_parameters);
        }

        e = av_open_input_file(&format_context, filename, input_format,
                               buf_size, format_parameters);

        ffmpeg_check_error(e);

        DATA_PTR(self) = format_context;

        return self;
      }
    C

    ##
    # :method: output_format

    builder.c <<-C
      VALUE output_format() {
        VALUE format_klass, obj;
        AVFormatContext* format_context;
        AVOutputFormat* output_format;

        format_klass = rb_path2class("FFMPEG::OutputFormat");

        Data_Get_Struct(self, AVFormatContext, format_context);

        if (format_context->oformat) {
          obj = Data_Wrap_Struct(format_klass, NULL, NULL,
                                 format_context->oformat);
        } else {
          obj = rb_funcall(format_klass, rb_intern("from"), 1, self);

          Data_Get_Struct(obj, AVOutputFormat, output_format);

          format_context->oformat = output_format;
        }

        return obj;
      }
    C

    ##
    # :method: output_format=

    builder.c <<-C
      VALUE output_format_equals(VALUE _output_format) {
        AVFormatContext *format_context;
        AVOutputFormat *output_format;

        Data_Get_Struct(self, AVFormatContext, format_context);
        Data_Get_Struct(_output_format, AVOutputFormat, output_format);

        format_context->oformat = output_format;

        return self;
      }
    C

    ##
    # :method: set_parameters

    builder.c <<-C
      VALUE set_parameters(VALUE _params) {
        AVFormatParameters *format_parameters;
        AVFormatContext *format_context;
        int e;

        Data_Get_Struct(self, AVFormatContext, format_context);
        Data_Get_Struct(_params, AVFormatParameters, format_parameters);

        e = av_set_parameters(format_context, format_parameters);

        ffmpeg_check_error(e);

        return self;
      }
    C

    ##
    # :method: stream_info

    builder.c <<-C
      VALUE stream_info() {
        AVFormatContext *format_context;
        int e;

        if (RTEST(rb_iv_get(self, "@stream_info")))
           return Qtrue;

        Data_Get_Struct(self, AVFormatContext, format_context);

        e = av_find_stream_info(format_context);

        ffmpeg_check_error(e);

        rb_iv_set(self, "@stream_info", Qtrue);

        return Qtrue;
       }
    C

    ##
    # :method: interleaved_write

    builder.c <<-C
      VALUE interleaved_write(VALUE _packet) {
        AVFormatContext *format_context;
        AVPacket *packet;
        int ret;

        Data_Get_Struct(self, AVFormatContext, format_context);
        Data_Get_Struct(_packet, AVPacket, packet);

        ret = av_interleaved_write_frame(format_context, packet);

        ffmpeg_check_error(ret);

        return INT2NUM(ret);
      }
    C

    ##
    # :method: new_output_stream

    builder.c <<-C
      VALUE new_output_stream() {
        AVFormatContext *format_context;
        AVStream *stream;
        VALUE stream_klass, obj;

        Data_Get_Struct(self, AVFormatContext, format_context);

        stream = av_new_stream(format_context, format_context->nb_streams);

        if (!stream) {
          rb_raise(rb_eNoMemError, "could not allocate stream");
        }

        stream_klass = rb_path2class("FFMPEG::Stream");

        obj = Data_Wrap_Struct(stream_klass, NULL, NULL, stream);

        rb_iv_set(obj, "@stream_info", Qtrue);
        rb_funcall(obj, rb_intern("initialize"), 1, self);

        return obj;
      }
    C

    ##
    # :method: read_frame

    builder.c <<-C
      VALUE read_frame(VALUE rb_packet) {
        AVFormatContext *format_context;
        AVPacket *packet;
        int e;

        Data_Get_Struct(self, AVFormatContext, format_context);
        Data_Get_Struct(rb_packet, AVPacket, packet);

        e = av_read_frame(format_context, packet);

        ffmpeg_check_error(e);

        // refresh the buffer
        rb_funcall(rb_packet, rb_intern("buffer"), 0);

        return Qtrue;
      }
    C

    ##
    # :method: streams

    builder.c <<-C
      VALUE streams() {
        int i;
        VALUE streams, stream, stream_klass;
        AVFormatContext *format_context;

        Data_Get_Struct(self, AVFormatContext, format_context);

        if (!RTEST(rb_iv_get(self, "@stream_info"))) {
          if (!RTEST(stream_info(self))) {
            return Qnil; /* HACK raise exception */
          }
        }

        streams = rb_ary_new();

        stream_klass = rb_path2class("FFMPEG::Stream");

        for (i = 0; i < format_context->nb_streams; i++) {
          stream = rb_funcall(stream_klass, rb_intern("from"), 2, self,
                              INT2NUM(i));
          rb_ary_push(streams, stream);
        }

        return streams;
      }
    C

    ##
    # :method: write_header

    builder.c <<-C
      VALUE write_header() {
        AVFormatContext *format_context;
        int e;

        Data_Get_Struct(self, AVFormatContext, format_context);

        e = av_write_header(format_context);

        ffmpeg_check_error(e);

        return self;
      }
    C

    ##
    # :method: write_trailer

    builder.c <<-C
      VALUE write_trailer() {
        AVFormatContext *format_context;
        int e;

        Data_Get_Struct(self, AVFormatContext, format_context);

        e = av_write_trailer(format_context);

        ffmpeg_check_error(e);

        return self;
      }
    C

    builder.struct_name = 'AVFormatContext'
    builder.reader :album,     'char *'
    builder.reader :author,    'char *'
    builder.reader :comment,   'char *'
    builder.reader :copyright, 'char *'
    builder.reader :filename,  'char *'
    builder.reader :genre,     'char *'
    builder.reader :title,     'char *'

    builder.accessor :loop_output, 'int'
    builder.accessor :max_delay,   'int'
    builder.accessor :preload,     'int'
    builder.accessor :bit_rate,    'int'

    builder.reader :track,       'int'
    builder.reader :year,        'int'

    ##
    # Duration in FFMPEG::TIME_BASE units

    builder.reader :duration,   'int64_t'
    builder.reader :file_size,  'int64_t'
    builder.reader :start_time, 'int64_t'
    builder.reader :timestamp,  'int64_t'
  end

  attr_reader :format_parameters

  attr_accessor :sync_pts

  ##
  # +file+ accepts a file name or an IO for output
  #
  # IO on output will make the output not seekable

  def initialize(file, output = false)
    @input = !output
    @timestamp_offset = 0
    @sync_pts = 0
    @video_stream = nil
    @stream_info = nil
    @format_parameters = FFMPEG::FormatParameters.new

    unless output then
      raise NotImplementedError, 'input from IO not supported' unless
        String === file

      open_input_file file, nil, 0, @format_parameters

      stream_info
    else
      @stream_info = true

      output_format = FFMPEG::OutputFormat.guess_format nil, file, nil

      self.output_format = output_format
      self.filename = file

      file = "pipe:#{file.fileno}" if IO === file

      open file, FFMPEG::URL_WRONLY
    end
  end

  ##
  # Is there an audio stream?

  def audio?
    !!audio_stream
  end

  ##
  # The first audio stream

  def audio_stream
    @audio_stream ||= streams.find do |stream|
      stream.codec_context.codec_type == :AUDIO
    end
  end

  def inspect
    "#<%s:0x%x @input=%p @stream_info=%p @sync_pts=%d>" % [
      self.class, object_id,
      @input, @stream_info, @sync_pts
    ]
  end

  def input?
    @input
  end

  def encode_fifo(output_context, output_stream)
    encoder = output_stream.codec_context

    frame_bytes = encoder.frame_size * encoder.bytes_per_sample *
      encoder.channels

    while output_stream.fifo.size >= frame_bytes do
      packet = FFMPEG::Packet.new
      encoded = "\0" * frame_bytes * 2 # HACK

      samples = "\0" * output_stream.fifo.size

      size = output_stream.fifo.size
      output_stream.fifo.read samples, frame_bytes

      encoder.encode_audio samples, encoded

      packet.buffer = encoded
      packet.stream_index = output_stream.stream_index

      if encoder.coded_frame and
         encoder.coded_frame.pts != FFMPEG::NOPTS_VALUE then
        packet.pts = FFMPEG::Rational.rescale_q(encoder.coded_frame.pts,
                                                encoder.time_base,
                                                output_stream.time_base)
      end

      packet.flags |= FFMPEG::Packet::FLAG_KEY

      output_context.interleaved_write packet

      output_context.sync_pts += encoder.frame_size
    end
  end

  def encode_frame(frame, output_stream)
    @output_buffer ||= FFMPEG::FrameBuffer.new 1048576
    @output_packet ||= FFMPEG::Packet.new
    packet = @output_packet.clean

    packet.stream_index = output_stream.stream_index

    encoder = output_stream.codec_context
    frame.pts = output_stream.sync_pts

    bytes = encoder.encode_video frame, @output_buffer

    packet.buffer = @output_buffer
    packet.size = bytes

    if encoder.coded_frame and
       encoder.coded_frame.pts != FFMPEG::NOPTS_VALUE then
      packet.pts = FFMPEG::Rational.rescale_q(encoder.coded_frame.pts,
                                              encoder.time_base,
                                              output_stream.time_base)
    else
      packet.pts = output_stream.sync_pts
    end

    if encoder.coded_frame and encoder.coded_frame.key_frame then
      packet.flags |= FFMPEG::Packet::FLAG_KEY
    end

    packet
  end

  def encode_samples(samples, input_stream, output_context, output_stream)
    encoder = output_stream.codec_context

    # FIXME FFMPEG says this is wrong, but not why
    output_stream.sync_pts = (input_stream.pts.to_f /
                              FFMPEG::TIME_BASE *
                              encoder.sample_rate).round -
                              output_stream.fifo.size / encoder.channels * 2

    if encoder.frame_size > 1 then
      output_stream.fifo.realloc output_stream.fifo.size + samples.length

      output_stream.fifo.write samples

      encode_fifo output_context, output_stream
    else
      raise NotImplementedError,
            "encoding #{encoder.frame_size} not implemented"
      packet = FFMPEG::Packet.new
      output_size = samples.length
      coded_bps = encodec.bytes_per_sample

      output_context.sync_pts += samples.length /
        encoder.bytes_per_sample * encoder.channels

      output_size /= encoder.bytes_per_sample

      output_size *= coded_bps if coded_bps > 0

      encoder.encode_audio blah

      packet.buffer = encoded
      packet.stream_index = output_stream.stream_index

      if encoder.coded_frame and
         encoder.coded_frame.pts != FFMPEG::NOPTS_VALUE then
        packet.pts = FFMPEG::Rational.rescale_q(encoder.coded_frame.pts,
                                                encoder.time_base,
                                                output_stream.time_base)
      end

      packet.flags |= FFMPEG::Packet::FLAG_KEY

      output_context.interleaved_write packet
    end
  end

  def output_audio(packet, output_context, output_stream, input_stream)
    decoder = input_stream.codec_context
    encoder = output_stream.codec_context
    encodec = encoder.codec
    samples = ''

    input_stream.next_pts = input_stream.pts if
      input_stream.next_pts == FFMPEG::NOPTS_VALUE

    if packet.dts != FFMPEG::NOPTS_VALUE then
      input_stream.pts = FFMPEG::Rational.rescale_q(packet.dts,
                                                    input_stream.time_base,
                                                    FFMPEG::TIME_BASE_Q)
      input_stream.next_pts = input_stream.pts
    end

    len = packet.size

    while len > 0 or
          (packet.nil? and input_stream.next_pts != input_stream.pts)
      input_stream.pts = input_stream.next_pts

      new_size = [packet.size * samples.length,
                  FFMPEG::Codec::MAX_AUDIO_FRAME_SIZE].max

      samples = "\0" * new_size if packet and samples.length < new_size

      bytes_used = decoder.decode_audio samples, packet

      len -= bytes_used

      next if samples.size == 0

      input_stream.next_pts += FFMPEG::TIME_BASE / 2 * samples.length /
        decoder.sample_rate * decoder.channels

      # done decoding audio

      encode_samples samples, input_stream, output_context, output_stream
    end
  end

  def output_video(packet, output_context, output_stream, input_stream)
    decoder = input_stream.codec_context
    encoder = output_stream.codec_context
    @in_frame ||= FFMPEG::Frame.from decoder

    input_stream.next_pts = input_stream.pts if
      input_stream.next_pts == FFMPEG::NOPTS_VALUE

    if packet.dts != FFMPEG::NOPTS_VALUE then
      input_stream.pts = FFMPEG::Rational.rescale_q(packet.dts,
                                                    input_stream.time_base,
                                                    FFMPEG::TIME_BASE_Q)
      input_stream.next_pts = input_stream.pts
    end

    len = packet.size

    while len > 0 or
          (packet.nil? and input_stream.next_pts != input_stream.pts)
      input_stream.pts = input_stream.next_pts

      data_size = decoder.width * decoder.height * 3 / 2

      @in_frame.defaults
      @in_frame.quality = input_stream.quality

      got_picture, bytes = decoder.decode_video @in_frame, packet

      break :fail if bytes.nil?

      @in_frame = nil unless got_picture

      if decoder.time_base.num != 0 then
        input_stream.next_pts += FFMPEG::TIME_BASE * decoder.time_base
      end

      len = 0

      # done decoding

      @scaler ||= FFMPEG::ImageScaler.for decoder, encoder, :BICUBIC

      output_stream.sync_pts =
        input_stream.pts.to_f / FFMPEG::TIME_BASE / encoder.time_base

      output_packet = output_context.encode_frame @scaler.scale(@in_frame),
                                                  output_stream

      output_context.interleaved_write output_packet if output_packet.size > 0

      output_context.sync_pts += 1
    end
  end

  def transcode_map(&block)
    stream_map = FFMPEG::StreamMap.new self

    yield stream_map

    raise FFMPEG::Error, 'map is empty' if stream_map.empty?

    prepare_transcoding stream_map

    # TODO do prep and transcode
    stream_map.output_format_contexts.each do |output_context|
      output_context.write_header
    end

    input_packet = FFMPEG::Packet.new

    eof = false
    packet_dts = 0

    loop do
      input_packet.clean

      begin
        read_frame input_packet
      rescue EOFError
        eof = true
      end

      # next unless input_packet.stream_index == video_stream.stream_index

      if input_packet.dts != FFMPEG::NOPTS_VALUE then
        input_packet.dts += FFMPEG::Rational.rescale_q(@timestamp_offset,
                                                       FFMPEG::TIME_BASE_Q,
                                                       video_stream.time_base)
      end

      if input_packet.pts != FFMPEG::NOPTS_VALUE then
        input_packet.pts += FFMPEG::Rational.rescale_q(@timestamp_offset,
                                                       FFMPEG::TIME_BASE_Q,
                                                       video_stream.time_base)
      end

      break :fail if input_packet.pts == FFMPEG::NOPTS_VALUE

      next unless stream_map.map[input_packet.stream_index]

      stream_map.map[input_packet.stream_index].each do |output_stream|
        case output_stream.type
        when :AUDIO then
          output_audio(input_packet, output_stream.format_context,
                       output_stream, streams[input_packet.stream_index])
        when :VIDEO then
          output_video(input_packet, output_stream.format_context,
                       output_stream, streams[input_packet.stream_index])
        else
          raise NotImplementedError,
                "#{output_stream.type} output not implemented"
        end
      end
    end

    stream_map.output_format_contexts.each do |output_context|
      output_context.write_trailer
    end
  end

  def prepare_transcoding(stream_map)
    stream_map.map.each_pair do |index, output_streams|
      # prepare input stream
      input_stream = streams[index]
      decoder = input_stream.codec_context

      video_stream.pts = 0
      video_stream.next_pts = FFMPEG::NOPTS_VALUE

      decoder.open decoder.decoder

      # prepare output streams
      output_streams.each do |output_stream|
        output_context = output_stream.format_context
        encoder = output_stream.codec_context

        output_context.preload = 0.5 * FFMPEG::TIME_BASE
        output_context.max_delay = 0.7 * FFMPEG::TIME_BASE
        output_context.loop_output = FFMPEG::OutputFormat::NO_OUTPUT_LOOP

        output_stream.sync_pts = 0

        if output_stream.duration.zero? then
          output_stream.duration = Rational.rescale_q(video_stream.duration,
                                                      video_stream.time_base,
                                                      output_video_stream.time_base)
        end

        # encoder.open FFMPEG::Codec.for_encoder(encoder.codec_id)

        case encoder.codec_type
        when :AUDIO then
          output_stream.fifo = FFMPEG::FIFO.new 0
        when :VIDEO then
          # TODO preserve ratio if width or height provided
          if encoder.width == 0
            encoder.width = decoder.width
            encoder.height = decoder.heigth
          end

          # encoder.sample_aspect_ratio.num = (4/3) * encoder.width / encoder.height
          # encoder.sample_aspect_ratio.den = 255

          encoder.bit_rate_tolerance = 0.2 * encoder.bit_rate if
          encoder.bit_rate_tolerance.zero?

          encoder.pixel_format = decoder.pixel_format if
            encoder.pixel_format == -1

          unless encoder.rc_initial_buffer_occupancy > 1 then
            encoder.rc_initial_buffer_occupancy =
              encoder.rc_buffer_size * 3 / 4
          end
        end
      end
    end
  end

  def output_stream(codec_type, codec_name = nil, options={})
    stream = new_output_stream
    stream.context_defaults codec_type

    codec_id = output_format.guess_codec codec_name, filename, nil, codec_type

    raise FFMPEG::Error, "unable to get codec #{codec_name}" unless codec_id
    codec = FFMPEG::Codec.for_encoder codec_id

    encoder = stream.codec_context
    encoder.defaults

    if output_format.flags & FFMPEG::FormatParameters::GLOBALHEADER ==
       FFMPEG::FormatParameters::GLOBALHEADER then
      encoder.flags |= FFMPEG::Codec::Flag::GLOBAL_HEADER
    end

    required = case codec_type
               when FFMPEG::Codec::VIDEO then
                 [:bit_rate, :width, :height]
               when FFMPEG::Codec::AUDIO then
                 [:bit_rate, :channels]
               else raise NotImplementedError,
                          "codec type #{codec_type} not supported"
               end

    (options.keys & required).each do |key|
      method = "#{key}=".to_sym
      raise ArgumentError, "required option #{key} not set" unless
        options.key? key
      stream.send  method, options[key] if stream.respond_to? method
      encoder.send method, options[key] if encoder.respond_to? method
    end

    case codec_type
    when FFMPEG::Codec::VIDEO then
      encoder.pixel_format = options[:pixel_format] || codec.pixel_formats[0]
      encoder.fps = options[:fps] || FFMPEG.Rational(25,1)
    when FFMPEG::Codec::AUDIO then
      sample_rate = options[:sample_rate] || 44100
      encoder.sample_rate = sample_rate
      encoder.fps = FFMPEG.Rational 1, sample_rate
    end

    encoder.bit_rate_tolerance =
      options[:bit_rate_tolerance] || encoder.bit_rate * 10 / 100

    encoder.codec_id = codec_id
    encoder.open codec

    stream
  end

  ##
  # Is there a video stream?

  def video?
    !!video_stream
  end

  ##
  # The first video stream

  def video_stream
    @video_stream ||= streams.find do |stream|
      stream.codec_context.codec_type == :VIDEO
    end
  end

end

