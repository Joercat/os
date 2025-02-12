#include <zlib.h>
#include <string>
#include <fstream>
#include <vector>

class Compressor {
private:
    z_stream strm;
    std::vector<uint8_t> buffer;

public:
    void compressFile(const std::string& input, const std::string& output) {
        std::ifstream inFile(input, std::ios::binary);
        std::ofstream outFile(output, std::ios::binary);
        
        // Read input file
        inFile.seekg(0, std::ios::end);
        size_t size = inFile.tellg();
        inFile.seekg(0);
        
        buffer.resize(size);
        inFile.read((char*)buffer.data(), size);
        
        // Initialize zlib
        deflateInit(&strm, Z_BEST_COMPRESSION);
        
        // Compress
        std::vector<uint8_t> outBuffer(size);
        strm.next_in = buffer.data();
        strm.avail_in = size;
        strm.next_out = outBuffer.data();
        strm.avail_out = size;
        
        deflate(&strm, Z_FINISH);
        
        // Write compressed data
        outFile.write((char*)outBuffer.data(), size - strm.avail_out);
        
        deflateEnd(&strm);
    }
};
