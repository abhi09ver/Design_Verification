cd /home/runner
export PATH=/usr/bin:/bin:/tool/pandora64/bin:/xcelium25.03/tools.lnx86/bin:/xcelium25.03/bin:/xcelium25.03/tools.lnx86/systemc/gcc/bin:/usr/local/bin
export IFV_HOME=/xcelium25.03
export LDV_TOOLS=/xcelium25.03/tools.lnx86
export SPMN_HOME=/xcelium25.03
export TOP_INSTALL_DIR=/xcelium25.03
export EDATOOL=xcelium
export LM_LICENSE_FILE=5280@10.116.0.5
export IUS_HOME=/xcelium25.03
export SOCV_KIT_HOME=/xcelium25.03
export SPECMAN_HOME=/xcelium25.03/specman
export EMGR_HOME=/xcelium25.03
export NCSIM_VERSION=25.03
export HOME=/home/runner
export LDV_HOME=/xcelium25.03
xrun -Q -unbuffered '-timescale' '1ns/1ns' '-sysv' '-access' '+rw' design.sv testbench.sv  ; echo 'Creating result.zip...' && zip -r /tmp/tmp_zip_file_123play.zip . && mv /tmp/tmp_zip_file_123play.zip result.zip