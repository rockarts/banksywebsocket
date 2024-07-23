A Swift client implementation of the RFC 6455 Websocket Standard


Frame Structure
```
0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-------+-+-------------+-------------------------------+
|F|R|R|R| opcode|M| Payload len |    Extended payload length    |
|I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
|N|V|V|V|       |S|             |   (if payload len==126/127)   |
| |1|2|3|       |K|             |                               |
+-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
|     Extended payload length continued, if payload len == 127  |
+ - - - - - - - - - - - - - - - +-------------------------------+
|                               |Masking-key, if MASK set to 1  |
+-------------------------------+-------------------------------+
| Masking-key (continued)       |          Payload Data         |
+-------------------------------- - - - - - - - - - - - - - - - +
:                     Payload Data continued ...                :
+ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
|                     Payload Data continued ...                |
+---------------------------------------------------------------+
```

Field Descriptions:
a. FIN (1 bit): Indicates if this is the final fragment in a message. The first fragment may also be the final fragment.
b. RSV1, RSV2, RSV3 (1 bit each): Reserved bits. Must be 0 unless an extension is negotiated that defines meanings for non-zero values.
c. Opcode (4 bits): Defines the interpretation of the payload data:

0x0: Continuation frame
0x1: Text frame
0x2: Binary frame
0x8: Connection close
0x9: Ping
0xA: Pong
Other values are reserved for future use

d. Mask (1 bit): Indicates whether the payload data is masked. If set to 1, a masking key is present in masking-key, and this is used to unmask the payload data.
e. Payload length (7 bits, 7+16 bits, or 7+64 bits):

If 0-125, that is the payload length.
If 126, the following 2 bytes interpreted as a 16-bit unsigned integer are the payload length.
If 127, the following 8 bytes interpreted as a 64-bit unsigned integer are the payload length.

f. Masking-key (0 or 4 bytes): All frames sent from the client to the server are masked by a 32-bit value that is contained within the frame.
g. Payload data: The actual data being transmitted. This is masked if the mask bit is set.
Masking:
If the mask bit is set, the payload data is masked using the masking key. Each octet of the payload data is XORed with an octet of the masking key, using modulo 4 to cycle through the masking key.
Fragmentation:
Messages can be split into multiple frames. The FIN bit and opcode are used to indicate the start, continuation, and end of a fragmented message.
Control Frames:
Opcodes 0x8 (Close), 0x9 (Ping), and 0xA (Pong) are control frames. They can be injected in the middle of a fragmented message and must not be fragmented themselves.
