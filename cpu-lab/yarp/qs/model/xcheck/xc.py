import sys,subprocess
sys.path.insert(0,sys.argv[1]); import rv32i
bad=0; files=sys.argv[2:]
for s in files:
    w,_=rv32i.assemble(open(s).read().splitlines())
    open('p.hex','w').write('\n'.join(f'{x:08x}' for x in w)+'\n')
    iss=rv32i.ISS(); iss.run(w)
    got=[int(l,16) for l in subprocess.run(['./xc','p.hex'],capture_output=True,text=True).stdout.split()]
    if got!=iss.x: bad+=1; print('MISMATCH',s,[ (i,hex(a),hex(b)) for i,(a,b) in enumerate(zip(got,iss.x)) if a!=b][:3])
print(f'{len(files)-bad}/{len(files)} programs agree (C++ model vs Python ISS)')
