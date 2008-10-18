require 'rubygems'
require 'inline'

##
# HACK use rb_ivar_get

module FFMPEG

  VERSION = '1.0.0'

  class Rational; end

  def self.builder_defaults(builder)
    if false then # MacPorts
      builder.add_compile_flags '-I/opt/local/include'
      builder.include '<ffmpeg/avcodec.h>'
      builder.include "<ffmpeg/avformat.h>\n#ifdef RSHIFT\n#undef RSHIFT\n#endif"
      builder.add_link_flags '-L/opt/local/lib/ -lavformat -lavcodec'
    else
      builder.add_compile_flags '-I/opt/ffmpeg/include'
      builder.include '<libavcodec/avcodec.h>'
      builder.include "<libavformat/avformat.h>\n#ifdef RSHIFT\n#undef RSHIFT\n#endif"
      builder.add_link_flags '-read_only_relocs suppress -L/opt/ffmpeg/lib/ -lavformat -lavcodec -lavutil'
    end

    builder.include_ruby_last

    builder.prefix <<-C
AVRational *ffmpeg_obj2rat(VALUE object);
VALUE ffmpeg_rat2obj(AVRational *rational);
    C

    builder.alias_type_converter 'long long', 'int64_t'
    builder.add_type_converter 'AVRational', 'ffmpeg_obj2rat', 'ffmpeg_rat2obj'
  end

  inline :C do |builder|
    FFMPEG.builder_defaults builder

    builder.prefix <<-C
AVRational *ffmpeg_obj2rat(VALUE object) {
  AVRational *rational;

  Data_Get_Struct(object, AVRational, rational);

  return rational;
}

VALUE ffmpeg_rat2obj(AVRational *rational) {
  VALUE klass;

  klass = rb_path2class("FFMPEG::Rational");

  return Data_Wrap_Struct(klass, 0, NULL, rational);
}
    C

    builder.add_to_init <<-C
      av_register_all();
      AVRational *time_base_q;
      time_base_q = (AVRational *)malloc(sizeof(AVRational));
      time_base_q->num = AV_TIME_BASE_Q.num;
      time_base_q->den = AV_TIME_BASE_Q.den;

      rb_define_const(c, "TIME_BASE_Q", ffmpeg_rat2obj(time_base_q));
    C

    builder.map_c_const 'AV_TIME_BASE'    => ['int', :TIME_BASE]
    builder.map_c_const 'URL_WRONLY'      => 'int'
    builder.map_c_const 'AV_NOPTS_VALUE'  => ['int64_t', :NOPTS_VALUE]
  end

end

require 'pp'
file = ARGV.shift
pp (FFMPEG::FormatContext.public_instance_methods - Object.public_instance_methods).sort
input = FFMPEG::FormatContext.new file



puts
puts "input streams:"
input.streams.each do |stream|
  puts "\t%2d %s time base: %f frame rate: %f" % [
    stream.stream_index,
    stream.codec_context.codec_type,
    stream.time_base.to_f,
    stream.r_frame_rate.to_f,
  ]
end
puts
puts "time base: #{FFMPEG::TIME_BASE} #{FFMPEG::TIME_BASE_Q.num}/#{FFMPEG::TIME_BASE_Q.den}"
puts

open 'out.mpeg', 'w' do |io|
  input.transcode 'mpeg', 'mpeg2video', 'mp3', io
end

