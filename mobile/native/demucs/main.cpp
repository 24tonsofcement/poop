// Bounded-memory Android driver for upstream Demucs.cpp (MIT).
// Same global normalization, 7.8s segments, shift and weighted overlap as upstream;
// completed output is streamed to disk instead of retaining six full-song tensors.
#include "model.hpp"
#include "dsp.hpp"
#include "tensor.hpp"
#include <fstream>
#include <filesystem>
#include <iostream>
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <array>
static uint32_t u32(std::istream &s) { uint32_t n=0; s.read((char*)&n,4); return n; }
static uint16_t u16(std::istream &s) { uint16_t n=0; s.read((char*)&n,2); return n; }
static void write32(std::ostream &s,uint32_t n){s.write((char*)&n,4);}
static void write16(std::ostream &s,uint16_t n){s.write((char*)&n,2);}
static void header(std::ostream &w,uint32_t bytes) {
 w.write("RIFF",4);write32(w,36+bytes);w.write("WAVEfmt ",8);write32(w,16);write16(w,1);write16(w,2);
 write32(w,44100);write32(w,176400);write16(w,4);write16(w,16);w.write("data",4);write32(w,bytes);
}
int main(int argc,char **argv) {
 try {
  if(argc!=4&&argc!=5)throw std::runtime_error("Expected model, PCM WAV and output folder");
  bool verify=argc==5&&std::string(argv[4])=="--verify";
  std::ifstream f(argv[2],std::ios::binary);char id[4];f.read(id,4);
  if(!f||std::memcmp(id,"RIFF",4))throw std::runtime_error("Expected WAV");
  u32(f);f.read(id,4);if(std::memcmp(id,"WAVE",4))throw std::runtime_error("Expected WAVE");
  uint16_t format=0,channels=0,bits=0;uint32_t rate=0,bytes=0;
  while(f.read(id,4)){uint32_t size=u32(f);auto start=f.tellg();
   if(!std::memcmp(id,"fmt ",4)){format=u16(f);channels=u16(f);rate=u32(f);u32(f);u16(f);bits=u16(f);}
   if(!std::memcmp(id,"data",4)){bytes=size;break;}f.seekg(start+std::streamoff(size+(size%2)));
  }
  if(format!=1||channels!=2||bits!=16||rate!=44100||bytes<8||bytes%4||bytes>44100u*4*900)throw std::runtime_error("Expected bounded 44.1k stereo PCM16 WAV");
  const int frames=bytes/4;const auto data_start=f.tellg();
  if(verify&&frames>44100*10)throw std::runtime_error("Reference verification limited to 10 seconds");
  // Two-pass whole-song mono statistics, without a full waveform allocation.
  double sum=0,squares=0;
  for(int i=0;i<frames;i++){float left=(int16_t)u16(f)/32768.f;float right=(int16_t)u16(f)/32768.f;double x=(left+right)*.5;sum+=x;squares+=x*x;}
  if(!f)throw std::runtime_error("Truncated WAV");
  float mean=sum/frames;float deviation=std::sqrt(std::max(0.,(squares-sum*sum/frames)/(frames-1)));
  if(deviation<1e-8)throw std::runtime_error("Audio has no usable signal");
  demucscpp::demucs_model model{};
  if(!demucscpp::load_demucs_model(argv[1],&model)||model.is_4sources)throw std::runtime_error("Six-source model load failed");
  const int segment=(int)(demucscpp::SEGMENT_LEN_SECS*44100);
  const int stride=(int)((1-demucscpp::OVERLAP)*segment);
  std::srand(1);const int shift=(int)(demucscpp::MAX_SHIFT_SECS*44100)-std::rand()%(int)(demucscpp::MAX_SHIFT_SECS*44100);
  const int length=frames+shift;
  demucscpp::demucs_segment_buffers buffers(2,segment,6);
  demucscpp::stft_buffers fft(buffers.padded_segment_samples);
  Eigen::VectorXf weight(segment);weight.setZero();
  weight.head(segment/2)=Eigen::VectorXf::LinSpaced(segment/2,1,segment/2);
  weight.tail(segment/2)=weight.head(segment/2).reverse();weight/=weight.maxCoeff();weight=weight.array().pow(demucscpp::TRANSITION_POWER);
  Eigen::MatrixXf ring=Eigen::MatrixXf::Zero(12,segment);Eigen::VectorXf sums=Eigen::VectorXf::Zero(segment);
  std::filesystem::path folder(argv[3]);std::filesystem::create_directories(folder);
  const char *names[]={"drums","bass","other","vocals","guitar","piano"};
  std::array<std::ofstream,6> raw;std::array<float,6> peaks{};
  for(int t=0;t<6;t++)raw[t].open(folder/(std::string(names[t])+".f32"),std::ios::binary);
  for(int offset=0;offset<length;offset+=stride) {
   const int count=std::min(segment,length-offset),leftpad=(segment-count)/2;
   buffers.mix.setZero();int first=std::max(0,shift-offset),last=std::min(count,frames+shift-offset);
   if(first<last){f.clear();f.seekg(data_start+std::streamoff((offset+first-shift)*4));
    for(int k=first;k<last;k++)for(int c=0;c<2;c++)buffers.mix(c,leftpad+k)=((int16_t)u16(f)/32768.f-mean)/deviation;
    if(!f)throw std::runtime_error("Input read failed");
   }
   const float progress=(float)offset/length;
   demucscpp::model_inference(model,buffers,fft,[](float p,const std::string&){std::cout<<"PROGRESS "<<p<<std::endl;},progress,(float)stride/length);
   for(int k=0;k<count;k++){sums(k)+=weight(k);for(int t=0;t<6;t++)for(int c=0;c<2;c++)ring(t*2+c,k)+=weight(k)*buffers.targets_out(t,c,k+leftpad);}
   const int flush=std::min(stride,length-offset);
   for(int k=0;k<flush;k++)if(offset+k>=shift&&offset+k<shift+frames){
    for(int t=0;t<6;t++)for(int c=0;c<2;c++){
     float v=ring(t*2+c,k)/sums(k)*deviation+mean;
     if(!std::isfinite(v))throw std::runtime_error("Non-finite separation output");
     peaks[t]=std::max(peaks[t],std::abs(v));raw[t].write((char*)&v,4);
    }
   }
   ring.leftCols(segment-flush)=ring.rightCols(segment-flush).eval();ring.rightCols(flush).setZero();
   sums.head(segment-flush)=sums.tail(segment-flush).eval();sums.tail(flush).setZero();
  }
  for(auto &w:raw){w.close();if(!w)throw std::runtime_error("Storage full while writing stems");}
  if(verify){
   f.clear();f.seekg(data_start);Eigen::MatrixXf audio(2,frames);
   for(int i=0;i<frames;i++)for(int c=0;c<2;c++)audio(c,i)=(int16_t)u16(f)/32768.f;
   std::srand(1);auto reference=demucscpp::demucs_inference(model,audio,[](float,const std::string&){});
   double error=0,energy=0;
   for(int t=0;t<6;t++){std::ifstream source(folder/(std::string(names[t])+".f32"),std::ios::binary);
    for(int i=0;i<frames;i++)for(int c=0;c<2;c++){float v;source.read((char*)&v,4);float ref=reference(t,c,i);error+=(v-ref)*(v-ref);energy+=ref*ref;}
   }
   double relative=std::sqrt(error/std::max(energy,1e-12));std::cout<<"REFERENCE_RELATIVE_RMS "<<relative<<std::endl;
   if(relative>.005)throw std::runtime_error("Streaming/reference inference mismatch");
  }
  for(int t=0;t<6;t++){
   auto path=folder/(std::string(names[t])+".f32");std::ifstream source(path,std::ios::binary);
   std::ofstream w(folder/(std::string(names[t])+".wav"),std::ios::binary);header(w,bytes);
   const float scale=std::max(1.f,peaks[t]/.99f);
   for(int i=0;i<frames*2;i++){float v;source.read((char*)&v,4);write16(w,(int16_t)(std::clamp(v/scale,-1.f,.999969f)*32768));}
   if(!source||!w)throw std::runtime_error("Cannot finish stem files");source.close();std::filesystem::remove(path);
  }
  return 0;
 }catch(const std::exception &e){std::cerr<<e.what()<<std::endl;return 1;}
}
