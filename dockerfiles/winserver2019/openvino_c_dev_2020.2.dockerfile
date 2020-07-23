# escape=`
FROM mcr.microsoft.com/windows/servercore:ltsc2019 AS ov_base

LABEL Description="This is the dev image for Intel(R) Distribution of OpenVINO(TM) toolkit on Windows Server LTSC 2019"
LABEL Vendor="Intel Corporation"

# Restore the default Windows shell for correct batch processing.
SHELL ["cmd", "/S", "/C"]

USER ContainerAdministrator


ARG HTTPS_PROXY



# setup MSBuild 2019
ARG VS_DIR=/temp/msbuild2019

WORKDIR ${VS_DIR}
COPY scripts\msbuild2019\ ${VS_DIR}
RUN vs_buildtools__1627812474.1585209146.exe --quiet --norestart --wait --nocache --noUpdateInstaller --noWeb `
     --add Microsoft.VisualStudio.Workload.MSBuildTools `
     --add Microsoft.VisualStudio.Workload.UniversalBuildTools `
     --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended `
     --channelUri C:\doesntExist.chman && powershell set-executionpolicy remotesigned

# Setup Redistributable Libraries for Intel(R) C++ Compiler for Windows*

RUN powershell.exe -Command `
    Invoke-WebRequest -URI https://software.intel.com/sites/default/files/managed/59/aa/ww_icl_redist_msi_2018.3.210.zip -Proxy %HTTPS_PROXY%  -OutFile "%TMP%\ww_icl_redist_msi_2018.3.210.zip" ; `
    Expand-Archive -Path "%TMP%\ww_icl_redist_msi_2018.3.210.zip" -DestinationPath "%TMP%\ww_icl_redist_msi_2018.3.210" -Force ; `
    Remove-Item "%TMP%\ww_icl_redist_msi_2018.3.210.zip" -Force

RUN %TMP%\ww_icl_redist_msi_2018.3.210\ww_icl_redist_intel64_2018.3.210.msi /quiet /passive /log "%TMP%\redist.log"

# setup CMake

RUN powershell.exe -Command `
    Invoke-WebRequest -URI https://cmake.org/files/v3.14/cmake-3.14.7-win64-x64.msi -Proxy %HTTPS_PROXY% -OutFile %TMP%\\cmake-3.14.7-win64-x64.msi ; `
    Start-Process %TMP%\\cmake-3.14.7-win64-x64.msi -ArgumentList '/quiet /norestart' -Wait ; `
    Remove-Item %TMP%\\cmake-3.14.7-win64-x64.msi -Force

RUN SETX /M PATH "C:\Program Files\CMake\Bin;%PATH%"

# setup Python
ARG PYTHON_VER=python3.7


RUN powershell.exe -Command `
  Invoke-WebRequest -URI https://www.python.org/ftp/python/3.7.6/python-3.7.6-amd64.exe -Proxy %HTTPS_PROXY% -OutFile %TMP%\\python-3.7.exe ; `
  Start-Process %TMP%\\python-3.7.exe -ArgumentList '/passive InstallAllUsers=1 PrependPath=1 TargetDir=c:\\Python37' -Wait ; `
  Remove-Item %TMP%\\python-3.7.exe -Force

RUN python -m pip install --upgrade pip
RUN python -m pip install cmake

# download package from external URL
ARG package_url
ARG TEMP_DIR=/temp

WORKDIR ${TEMP_DIR}
# hadolint ignore=DL3020
ADD ${package_url} ${TEMP_DIR}

# install product by copying archive content
ARG build_id
ENV INTEL_OPENVINO_DIR C:\intel\openvino_${build_id}

RUN powershell.exe -Command `
    Expand-Archive -Path "./*.zip" -DestinationPath "%INTEL_OPENVINO_DIR%" -Force ; `
    Remove-Item "./*.zip" -Force

WORKDIR C:\intel
RUN mklink /D openvino %INTEL_OPENVINO_DIR%

WORKDIR ${TEMP_DIR}
COPY scripts\create_symlinks.bat create_symlinks.bat
RUN create_symlinks.bat %INTEL_OPENVINO_DIR%

# for CPU

# dev package
WORKDIR ${INTEL_OPENVINO_DIR}
RUN python -m pip install --no-cache-dir setuptools && `
    python -m pip install --no-cache-dir -r "%INTEL_OPENVINO_DIR%\python\%PYTHON_VER%\requirements.txt" && `
    python -m pip install --no-cache-dir -r "%INTEL_OPENVINO_DIR%\python\%PYTHON_VER%\openvino\tools\benchmark\requirements.txt" && `
    python -m pip install --no-cache-dir torch==1.4.0+cpu torchvision==0.5.0+cpu -f https://download.pytorch.org/whl/torch_stable.html

WORKDIR ${TEMP_DIR}
COPY scripts\install_requirements.bat install_requirements.bat
RUN install_requirements.bat %INTEL_OPENVINO_DIR%


WORKDIR ${INTEL_OPENVINO_DIR}\deployment_tools\open_model_zoo\tools\accuracy_checker
RUN %INTEL_OPENVINO_DIR%\bin\setupvars.bat && `
    python -m pip install --no-cache-dir -r "%INTEL_OPENVINO_DIR%\deployment_tools\open_model_zoo\tools\accuracy_checker\requirements.in" && `
    python "%INTEL_OPENVINO_DIR%\deployment_tools\open_model_zoo\tools\accuracy_checker\setup.py" install

WORKDIR ${INTEL_OPENVINO_DIR}\deployment_tools\tools\post_training_optimization_toolkit
RUN python -m pip install --no-cache-dir -r "%INTEL_OPENVINO_DIR%\deployment_tools\tools\post_training_optimization_toolkit\requirements.txt" && `
    python "%INTEL_OPENVINO_DIR%\deployment_tools\tools\post_training_optimization_toolkit\setup.py" install



WORKDIR ${INTEL_OPENVINO_DIR}

# Post-installation cleanup
RUN powershell Remove-Item -Force -Recurse "%TEMP%\*" && `
    powershell Remove-Item -Force -Recurse "%TEMP_DIR%" && `
    rmdir /S /Q "%ProgramData%\Package Cache"

USER ContainerUser

CMD ["cmd.exe"]

# Setup custom layers
