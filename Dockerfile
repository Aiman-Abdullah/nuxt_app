# stage 1: base (intermediary image)
# purpose: set env variables and install prod dependencies
FROM node:14-alpine as base

# set basic env variables (can be overridden by docker compose, docker swarm, or in a k8s cluster)
ENV NODE_ENV production
ENV PORT 3000
ENV HOST 0.0.0.0
ENV API_PREFIX /nuxtapi
ENV LOG ERROR
ENV TINI_VERSION 0.19.0-r0
ENV IDLE_TIME 1200000
ENV NUXT_HOST=0.0.0.0
ENV NUXT_PORT=3000

# download tini
RUN apk update \
    && apk add tini=${TINI_VERSION} --no-cache
ENTRYPOINT ["/sbin/tini", "--"]

# add .bin node_modules folder to the PATH env variable
# this is to avoid executing npm commands on the CMD stanzas and be more explicit on what you are executing
ENV PATH /node/node_modules/.bin:$PATH

# mkdir /node && cd /node
WORKDIR /node

# node user as owner of this folder
RUN chown -R node:node .

# pass dependency structure files
COPY --chown=node:node package.json package-lock.json* ./

# install ONLY prod dependencies (for a minified bundle)
RUN npm config list \
    && npm ci --only=production -timeout=9999999 \
    && npm cache clean --force -timeout=9999999

# this EXPOSE stanza is for informational purposes only: the nuxt prod server will
# be available on port 3000 by default
EXPOSE 3000

# source image (intermediary)
# purpose: copy source code
FROM base as source

# copy all of the code (make node user owner)
COPY --chown=node:node . .

# build image (intermediary)
# purpose: generate the standalone, bundled .nuxt/ folder to deploy our app to production
FROM source as build
# use nuxt-ts to build the application (the --standalone flag informs nuxt to bundle required node_modules/ inside the .nuxt/ folder)
RUN npm run build

# production image
# purpose: deploy the production server of this application
FROM base as prod

# keep track of commit and date
# PowerShell users
# command for CREATED_DATE: Get-Date -UFormat "%Y-%m-%dT%H:%M:%SZ"
# command for SOURCE_COMMIT: git rev-parse HEAD
ARG CREATED_DATE=not-set
ARG SOURCE_COMMIT=not-set

# copy the nuxt.config.js file, the static/ folder, the server-middleware/ folder (not bundled in .nuxt/ since it gets executed on runtime,
# and the infamous standalone .nuxt/ folder); this is all we need
# COPY --chown=node:node --from=build /node/src/static ./src/static
COPY --chown=node:node --from=build /node/nuxt.config.js ./
# COPY --chown=node:node --from=build /node/src/server-middleware ./src/server-middleware
COPY --chown=node:node --from=build /node/.nuxt ./.nuxt

# switch from root to node user (for security reasons; what happens if an intruder manages to get inside our container?
# the most we can do is provide that intruder with limited access to the container's file system)
USER node

# run the production server (nuxt-ts is a dev dependency, so use the nuxt binary)
CMD [ "nuxt", "start" ]
