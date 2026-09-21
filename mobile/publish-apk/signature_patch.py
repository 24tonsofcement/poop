"""Publish a locally signed APK without sending any private signing material.
The patch consists ONLY of public APK bytes and copies from the tested CI APK.
"""
import base64,gzip,hashlib,json,mmap,struct,sys,zipfile
from pathlib import Path

def digest(path):
    with open(path,'rb') as f:return hashlib.file_digest(f,'sha256').hexdigest() if hasattr(hashlib,'file_digest') else _digest(f)
def _digest(f):
    h=hashlib.sha256()
    for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()
def data_offset(data,info):
    assert data[info.header_offset:info.header_offset+4]==b'PK\x03\x04'
    names,extra=struct.unpack_from('<HH',data,info.header_offset+26)
    return info.header_offset+30+names+extra

def create(original,signed,output,run_id,commit,fingerprint):
    # APK signature metadata is public. The private signing key is never read here.
    with open(original,'rb') as a,open(signed,'rb') as b,zipfile.ZipFile(original) as az,zipfile.ZipFile(signed) as bz:
        aa=mmap.mmap(a.fileno(),0,access=mmap.ACCESS_READ);bb=mmap.mmap(b.fileno(),0,access=mmap.ACCESS_READ)
        old={i.filename:i for i in az.infolist()};ranges=[]
        for entry in bz.infolist():
            match=old.get(entry.filename)
            if not match or match.compress_size!=entry.compress_size or match.CRC!=entry.CRC or entry.compress_size<4096:continue
            source=data_offset(aa,match);target=data_offset(bb,entry);size=entry.compress_size
            same=all(aa[source+i:source+min(size,i+1048576)]==bb[target+i:target+min(size,i+1048576)] for i in range(0,size,1048576))
            if same:ranges.append((target,source,size))
        operations=[];cursor=0
        for target,source,size in sorted(ranges):
            if target>cursor:operations.append({'bytes':base64.b64encode(bb[cursor:target]).decode()})
            operations.append({'copy':[source,size]});cursor=target+size
        if cursor<len(bb):operations.append({'bytes':base64.b64encode(bb[cursor:]).decode()})
        payload={'source_sha256':digest(original),'target_sha256':digest(signed),'operations':operations}
        Path(output).write_text(base64.b64encode(gzip.compress(json.dumps(payload,separators=(',',':')).encode())).decode())
        Path(output).with_suffix('.json').write_text(json.dumps({'source_run':int(run_id),'source_commit':commit,'certificate_sha256':fingerprint,'apk_sha256':payload['target_sha256']},indent=2))
        aa.close();bb.close()

def apply(original,patch,output):
    payload=json.loads(gzip.decompress(base64.b64decode(Path(patch).read_text())))
    if digest(original)!=payload['source_sha256']:raise ValueError('CI APK does not match the tested signing source')
    with open(original,'rb') as source,open(output,'wb') as dest:
        for item in payload['operations']:
            if 'copy' in item:
                start,size=item['copy'];source.seek(start)
                while size:
                    data=source.read(min(size,1048576))
                    if not data:raise ValueError('Truncated APK source')
                    dest.write(data);size-=len(data)
            else:dest.write(base64.b64decode(item['bytes']))
    if digest(output)!=payload['target_sha256']:raise ValueError('Signed APK reconstruction checksum mismatch')

if __name__=='__main__':
    if sys.argv[1]=='apply':apply(*sys.argv[2:])
    elif sys.argv[1]=='create':create(*sys.argv[2:])
    else:raise SystemExit('Use create or apply')
