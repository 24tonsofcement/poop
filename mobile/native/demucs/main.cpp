// Android driver: bounded 16-bit PCM IO, same upstream six-source inference.
#include "model.hpp"
#include "dsp.hpp"
#include "tensor.hpp"
#include <fstream>
#include <filesystem>
#include <iostream>
#include <algorithm>
#include <cstdint>
#include <cstring>
static uint32_t u32(std::istream &s) { uint32_t n=0; s.read((char*)&n,4); return n; }
static uint16_t u16(std::istream &s) { uint16_t n=0; s.read((char*)&n,2); return n; }
static void write32(std::ostream &s,uint32_t n){s.write((char*)&n,4);}
static void write16(std::ostream &s,uint16_t n){s.write((char*)&n,2);}
int main(int argc,char **argv) {
 try {
  if(argc!=4) throw std::runtime_error("Expected model, PCM WAV and output folder");
  std::ifstream f(argv[2],std::ios::binary); char id[4]; f.read(id,4);
  if(std::memcmp(id,"RIFF",4)) throw std::runtime_error("Expected WAV");
  u32(f);f.read(id,4); if(std::memcmp(id,"WAVE",4)) throw std::runtime_error("Expected WAVE");
  uint16_t format=0,channels=0,bits=0;uint32_t rate=0,bytes=0;
  while(f.read(id,4)) {uint32_t size=u32(f);auto start=f.tellg();
   if(!std::memcmp(id,"fmt ",4)){format=u16(f);channels=u16(f);rate=u32(f);u32(f);u16(f);bits=u16(f);}
   if(!std::memcmp(id,"data",4)){bytes=size;break;}
   f.seekg(start+std::streamoff(size+(size%2)));
  }
  if(format!=1||channels!=2||bits!=16||rate!=44100||!bytes||bytes>44100u*4*900) throw std::runtime_error("Expected bounded 44.1k stereo PCM16 WAV");
  size_t frames=bytes/4;Eigen::MatrixXf audio(2,frames);
  for(size_t i=0;i<frames;i++) for(int c=0;c<2;c++){int16_t n=(int16_t)u16(f); audio(c,i)=n/32768.f;}
  if(!f) throw std::runtime_error("Truncated WAV");
  demucscpp::demucs_model model{};
  if(!demucscpp::load_demucs_model(argv[1],&model)||model.is_4sources) throw std::runtime_error("Six-source model load failed");
  auto out=demucscpp::demucs_inference(model,audio,[](float p,const std::string &){std::cout<<"PROGRESS "<<p<<std::endl;});
  std::filesystem::create_directories(argv[3]);
  const char *names[]={"drums","bass","other","vocals","guitar","piano"};
  for(int t=0;t<6;t++) {
   std::ofstream w(std::filesystem::path(argv[3])/(std::string(names[t])+".wav"),std::ios::binary);
   w.write("RIFF",4);write32(w,36+bytes);w.write("WAVEfmt ",8);write32(w,16);write16(w,1);write16(w,2);write32(w,44100);write32(w,176400);write16(w,4);write16(w,16);w.write("data",4);write32(w,bytes);
   for(size_t i=0;i<frames;i++)for(int c=0;c<2;c++)write16(w,(int16_t)(std::clamp(out(t,c,i),-1.f,.999969f)*32768));
   if(!w)throw std::runtime_error("Cannot write stem");
  }
  return 0;
 }catch(const std::exception &e){std::cerr<<e.what()<<std::endl;return 1;}
}
