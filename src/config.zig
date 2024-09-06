pub const PORT = 1883;
pub const QUEUE_DEPTH = 256;
pub const MAX_MESSAGE_LEN = 2048;
pub const MAX_CLIENT_ID_LEN = 64;

// TODO: make the  buffers longer, e.g. 2097152 max packet size to handle large payloads, etc.
pub const READ_BUFFER_SIZE = 1024;
pub const WRITE_BUFFER_SIZE = 1024;
