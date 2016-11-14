local ffi = require("ffi")
local lib = ffi.load("libopus.dll")

ffi.cdef[[
/* opus_types.h typedefs */
typedef int16_t opus_int16;
typedef int32_t opus_int32;
typedef uint16_t opus_uint16;
typedef uint32_t opus_uint32;

/* opus.h typedefs */
typedef struct OpusEncoder OpusEncoder;
typedef struct OpusDecoder OpusDecoder;
typedef struct OpusRepacketizer OpusRepacketizer;

/* opus.h encoder functions */
int opus_encoder_get_size(int channels);
OpusEncoder *opus_encoder_create(opus_int32 Fs, int channels, int application, int *error);
int opus_encoder_init(OpusEncoder *st, opus_int32 Fs, int channels, int application);
opus_int32 opus_encode(OpusEncoder *st, const opus_int16 *pcm, int frame_size, unsigned char *data, opus_int32 max_data_bytes);
opus_int32 opus_encode_float(OpusEncoder *st, const float *pcm, int frame_size, unsigned char *data, opus_int32 max_data_bytes);
void opus_encoder_destroy(OpusEncoder *st);
int opus_encoder_ctl(OpusEncoder *st, int request, ...);

/* opus.h decoder functions */
int opus_decoder_get_size(int channels);
OpusDecoder *opus_decoder_create(opus_int32 Fs, int channels, int *error);
int opus_decoder_init(OpusDecoder *st, opus_int32 Fs, int channels);
int opus_decode(OpusDecoder *st, const unsigned char *data, opus_int32 len, opus_int16 *pcm, int frame_size, int decode_fec);
int opus_decode_float(OpusDecoder *st, const unsigned char *data, opus_int32 len, float *pcm, int frame_size, int decode_fec);
void opus_decoder_destroy(OpusDecoder *st);
int opus_decoder_ctl(OpusDecoder *st, int request, ...);
int opus_packet_parse(const unsigned char *data, opus_int32 len, unsigned char *out_toc, const unsigned char *frames[48], opus_int16 size[48], int *payload_offset);
int opus_packet_get_bandwidth(const unsigned char *data);
int opus_packet_get_samples_per_frame(const unsigned char *data, opus_int32 Fs);
int opus_packet_get_nb_channels(const unsigned char *data);
int opus_packet_get_nb_frames(const unsigned char packet[], opus_int32 len);
int opus_packet_get_nb_samples(const unsigned char packet[], opus_int32 len, opus_int32 Fs);
int opus_decoder_get_nb_samples(const OpusDecoder *dec, const unsigned char packet[], opus_int32 len);
void opus_pcm_soft_clip(float *pcm, int frame_size, int channels, float *softclip_mem);

/* opus.h repacketizer functions */
int opus_repacketizer_get_size(void);
OpusRepacketizer *opus_repacketizer_init(OpusRepacketizer *rp);
OpusRepacketizer *opus_repacketizer_create(void);
void opus_repacketizer_destroy(OpusRepacketizer *rp);
int opus_repacketizer_cat(OpusRepacketizer *rp, const unsigned char *data, opus_int32 len);
opus_int32 opus_repacketizer_out_range(OpusRepacketizer *rp, int begin, int end, unsigned char *data, opus_int32 maxlen);
int opus_repacketizer_get_nb_frames(OpusRepacketizer *rp);
opus_int32 opus_repacketizer_out(OpusRepacketizer *rp, unsigned char *data, opus_int32 maxlen);
int opus_packet_pad(unsigned char *data, opus_int32 len, opus_int32 new_len);
opus_int32 opus_packet_unpad(unsigned char *data, opus_int32 len);
int opus_multistream_packet_pad(unsigned char *data, opus_int32 len, opus_int32 new_len, int nb_streams);
opus_int32 opus_multistream_packet_unpad(unsigned char *data, opus_int32 len, int nb_streams);

/* opus_defines.h library information functions */
const char *opus_strerror(int error);
const char *opus_get_version_string(void);
]]

-- TODO: opus_multistream.h and opus_custom.h

-- enumerations --

local function enum(tbl)
	local ret = {}
	for k, v in pairs(tbl) do
		assert(not ret[v], "enum clash")
		ret[v] = k
	end
	return setmetatable(tbl, {
		__call = function(_, k)
			return ret[k]
		end
	})
end

local Application = enum {
	VOIP = 2048,
	Audio = 2049,
	RestrictedLowDelay = 2051,
}

local Bandwidth = enum {
	Default = -1000,
	Narrowband = 1101,
	Mediumband = 1102,
	Wideband = 1103,
	SuperWideband = 1104,
	Fullband = 1105,
}

local Channel = enum {
	Default = -1000,
	Mono = 1,
	Stereo = 2,
}

local FrameSize = enum {
	Default = 5000,
	["2.5ms"] = 5001,
	["5ms"] = 5002,
	["10ms"] = 5003,
	["20ms"] = 5004,
	["40ms"] = 5005,
	["60ms"] = 5006,
}

local Signal = enum {
	Default = -1000,
	Voice = 3001,
	Music = 3002,
}

-- CTL requests --

local encoder_get = {
	bandwidth = 4009,
	sample_rate = 4029,
	final_range = 4031,
	application = 4001,
	bitrate = 4003,
	max_bandwidth = 4005,
	vbr = 4007,
	complexity = 4011,
	inband_fec = 4013,
	packet_loss_perc = 4015,
	dtx = 4017,
	vbr_constraint = 4021,
	force_channels = 4023,
	signal = 4025,
	lookahead = 4027,
	lsb_depth = 4037,
	expert_frame_duration = 4041,
	prediction_disabled = 4043,
}

local decoder_get = {
	bandwidth = 4009,
	sample_rate = 4029,
	final_range = 4031,
	gain = 4045,
	pitch = 4033,
	last_packet_duration = 4039,
}

local encoder_set = {
	application = 4000,
	bitrate = 4002,
	max_bandwidth = 4004,
	vbr = 4006,
	bandwidth = 4008,
	complexity = 4010,
	inband_fec = 4012,
	packet_loss_perc = 4014,
	dtx = 4016,
	vbr_constraint = 4020,
	force_channels = 4022,
	signal = 4024,
	lsb_depth = 4036,
	expert_frame_duration = 4040,
	prediction_disabled = 4042,
}

local decoder_set = {
	gain = 4034,
}

-- utilities --

local function throw(code)
	local version = ffi.string(lib.opus_get_version_string())
	local message = ffi.string(lib.opus_strerror(code))
	return error(string.format("[%s] %s", version, message))
end

local int_ptr = ffi.typeof("int[1]")
local opus_int32 = ffi.typeof("opus_int32")
local opus_int32_ptr = ffi.typeof("opus_int32[1]")

-- OpusEncoder --

local Encoder = {}
Encoder.__index = Encoder

setmetatable(Encoder, {__call = function(self, sample_rate, channels, app)

	app = app or Application.Audio

	local err = int_ptr(0)
	local state = lib.opus_encoder_create(sample_rate, channels, app, err)
	if err[0] < 0 then return throw(err[0]) end

	err = lib.opus_encoder_init(state, sample_rate, channels, app)
	if err < 0 then return throw(err) end

	return setmetatable({state}, self)

end})

function Encoder:get(k)

	local id = encoder_get[k]
	if not id then return throw(-1) end

	local ret = opus_int32_ptr(0)
	lib.opus_encoder_ctl(self[1], id, ret)
	ret = ret[0]

	if ret < 0 and ret ~= -1000 then return throw(ret) end
	return ret

end

function Encoder:set(k, v)

	local id = encoder_set[k]
	if not id then return throw(-1) end

	v = tonumber(v)
	if not v then return throw(-1) end
	local ret = lib.opus_encoder_ctl(self[1], id, opus_int32(v))

	if ret < 0 and ret ~= -1000 then return throw(ret) end
	return ret

end

function Encoder:reset()
	local ret = lib.opus_encoder_ctl(self[1], 4028)
	if ret < 0 and ret ~= -1000 then return throw(ret) end
	return ret
end

-- OpusDecoder --

local Decoder = {}
Decoder.__index = Decoder

setmetatable(Decoder, {__call = function(self, sample_rate, channels)

	local err = int_ptr(0)
	local state = lib.opus_decoder_create(sample_rate, channels, err)
	if err[0] < 0 then return throw(err[0]) end

	err = lib.opus_decoder_init(state, sample_rate, channels)
	if err < 0 then return throw(err) end

	return setmetatable({state}, self)

end})

function Decoder:get(k)

	local id = decoder_get[k]
	if not id then return throw(-1) end

	local ret = opus_int32_ptr(0)
	lib.opus_decoder_ctl(self[1], id, ret)
	ret = ret[0]

	if ret < 0 and ret ~= -1000 then return throw(ret) end
	return ret

end

function Decoder:set(k, v)

	local id = decoder_set[k]
	if not id then return throw(-1) end

	v = tonumber(v)
	if not v then return throw(-1) end
	local ret = lib.opus_decoder_ctl(self[1], id, opus_int32(v))

	if ret < 0 and ret ~= -1000 then return throw(ret) end
	return ret

end

function Decoder:reset()
	local ret = lib.opus_decoder_ctl(self[1], 4028)
	if ret < 0 and ret ~= -1000 then return throw(ret) end
	return ret
end

return {
	Application = Application,
	Bandwidth = Bandwidth,
	Channel = Channel,
	Encoder = Encoder,
	FrameSize = FrameSize,
	Signal = Signal,
}
