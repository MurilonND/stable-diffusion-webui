# sets the base image
FROM alpine/git:2.36.2 as download

# copies the file clone.sh from the local directory 
COPY clone.sh /clone.sh

# this command executes the clone.sh script with the project taming-transformers and the 24268930bf1dce879235a7fddd0b2355b84d7ea6 commit branch and remove the assets
RUN . /clone.sh taming-transformers https://github.com/CompVis/taming-transformers.git 24268930bf1dce879235a7fddd0b2355b84d7ea6 \ && rm -rf data assets **/*.ipynb

# this command executes the clone.sh script with the forked version of /stable-diffusion-webui and the maste branch
RUN . /clone.sh stable-diffusion https://github.com/MurilonND/stable-diffusion-webui.git master \
  && rm -rf assets data/**/*.png data/**/*.jpg data/**/*.gif

# this command another repositories, they are used in the code
RUN . /clone.sh CodeFormer https://github.com/sczhou/CodeFormer.git c5b4593074ba6214284d6acd5f1719b6c5d739af \ && rm -rf assets inputs
RUN . /clone.sh BLIP https://github.com/salesforce/BLIP.git 48211a1594f1321b00f14c9f7a5b4813144b2fb9
RUN . /clone.sh k-diffusion https://github.com/crowsonkb/k-diffusion.git 5b3af030dd83e0297272d861c19477735d0317ec
RUN . /clone.sh clip-interrogator https://github.com/pharmapsychotic/clip-interrogator 2486589f24165c8e3b303f84e9dbbea318df83e8

# sets the base image
FROM alpine:3.17 as xformers

# installs the aria2 package
RUN apk add --no-cache aria2

# download the specified wheel file (built-package format used for Python distributions)
RUN aria2c -x 5 --dir / --out wheel.whl 'https://github.com/AbdBarho/stable-diffusion-webui-docker/releases/download/6.0.0/xformers-0.0.21.dev544-cp310-cp310-manylinux2014_x86_64-pytorch201.whl'

# sets the base image
FROM python:3.10.9-slim

# sets environment variables 
ENV DEBIAN_FRONTEND=noninteractive PIP_PREFER_BINARY=1

# this updates the package index, then installs a list of packages
RUN --mount=type=cache,target=/var/cache/apt \
  apt-get update && \
  # we need those
  apt-get install -y fonts-dejavu-core rsync git jq moreutils aria2 \
  # extensions needs those
  ffmpeg libglfw3-dev libgles2-mesa-dev pkg-config libcairo2 libcairo2-dev build-essential

# this downloads the specified PyTorch wheel file and installs it along with the torchvision 
RUN --mount=type=cache,target=/cache --mount=type=cache,target=/root/.cache/pip \
  aria2c -x 5 --dir /cache --out torch-2.0.1-cp310-cp310-linux_x86_64.whl -c \
  https://download.pytorch.org/whl/cu118/torch-2.0.1%2Bcu118-cp310-cp310-linux_x86_64.whl && \
  pip install /cache/torch-2.0.1-cp310-cp310-linux_x86_64.whl torchvision --index-url https://download.pytorch.org/whl/cu118


# this clones the "stable-diffusion-webui" repository and installs the requirements
RUN --mount=type=cache,target=/root/.cache/pip \
  git clone https://github.com/MurilonND/stable-diffusion-webui.git && \
  cd stable-diffusion-webui && \
  # git reset --hard 20ae71faa8ef035c31aa3a410b707d792c8203a3 && \
  pip install -r requirements_versions.txt

# this installs the xformers package
RUN --mount=type=cache,target=/root/.cache/pip  \
  --mount=type=bind,from=xformers,source=/wheel.whl,target=/xformers-0.0.21.dev544-cp310-cp310-manylinux2014_x86_64.whl \
  pip install /xformers-0.0.21.dev544-cp310-cp310-manylinux2014_x86_64.whl

# sets environment variables 
ENV ROOT=/stable-diffusion-webui

# this copies the contents of the "/repositories" from the "download" build stage to the /stable-diffusion-webui/repositories/ directory in the current build stage
COPY --from=download /repositories/ ${ROOT}/repositories/

# this creates a new directory "${ROOT}/interrogate" and copies the contents of "${ROOT}/repositories/clip-interrogator/data/" into it
RUN mkdir ${ROOT}/interrogate && cp ${ROOT}/repositories/clip-interrogator/data/* ${ROOT}/interrogate

# this installs the Python packages specified in the requirements from the "${ROOT}/repositories/CodeFormer/" directory
RUN --mount=type=cache,target=/root/.cache/pip \
  pip install -r ${ROOT}/repositories/CodeFormer/requirements.txt

# this installs several Python packages (they are used by the code)
RUN --mount=type=cache,target=/root/.cache/pip \
  pip install pyngrok \
  git+https://github.com/TencentARC/GFPGAN.git@8d2447a2d918f8eba5a4a01463fd48e45126a379 \
  git+https://github.com/openai/CLIP.git@d50d76daa670286dd6cacf3bcd80b5e4823fc8e1 \
  git+https://github.com/mlfoundations/open_clip.git@bb6e834e9c70d9c27d0dc3ecedeebeaeb1ffad6b

### Note: don't update the sha of previous versions because the install will take forever
### instead, update the repo state in a later step

### TODO: either remove if fixed in A1111 (unlikely) or move to the top with other apt stuff

# this installs the libgoogle-perftools-dev package and then cleans the package cache.
RUN apt-get -y install libgoogle-perftools-dev && apt-get clean

# sets environment variables 
ENV LD_PRELOAD=libtcmalloc.so

# dont seen to be aplyed for this project
# ARG SHA=394ffa7b0a7fff3ec484bcd084e673a8b301ccc8

# RUN --mount=type=cache,target=/root/.cache/pip \
#   cd stable-diffusion-webui && \
#   git fetch && \
#   git reset --hard ${SHA} && \
#   pip install -r requirements_versions.txt

# this copies the contents of the local directory to the /docker directory
COPY . /docker

# this runs the script info.py
RUN \
  python3 /docker/info.py ${ROOT}/modules/ui.py && \
  # mv ${ROOT}/style.css ${ROOT}/user.css && \
  ### one of the ugliest hacks I ever wrote \
  # it modifies a file located at "/usr/local/lib/python3.10/site-packages/gradio/routes.py" by replacing a specific line using sed command
  sed -i 's/in_app_dir = .*/in_app_dir = True/g' /usr/local/lib/python3.10/site-packages/gradio/routes.py && \
  # it adds a configuration to the global Git settings to allow all directories to be considered safe.
  git config --global --add safe.directory '*'

# this sets the working directory to "${ROOT}"
WORKDIR ${ROOT}

# this sets environment variables 
ENV NVIDIA_VISIBLE_DEVICES=all

# this sets environment variables 
ENV CLI_ARGS="--api"

# this exposes port 7860
EXPOSE 7860

# this sets the entrypoint of the Docker image to "/docker/entrypoint.sh"
ENTRYPOINT ["/docker/entrypoint.sh"]

# this sets the default command to execute when the container starts (start automatic1111 as an API)
CMD python -u webui.py --listen --port 7860 ${CLI_ARGS}