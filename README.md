# Message broker

## How to use

- download source codes
  ```
  git clone https://github.com/Okestro-symphony/message-broker.git
  ```

- move the directory for message broker
  ```
  cd message-broker
  ```

### running in docker

- build the server for docker image
  ```
  make build-docker
  ```

- push docker image to your repository
  ```
  docker push <your image name>
  ```

- run the server as docker container
  ```
  make run-docker
  ```

- remove the server image from docker
  ```
  make rm-docker
  ```

### running in kubernetes

- deploy replicationcontroller 
  ```
  kubectl create -f kube/rc.yaml
  ```
  > if necessary, change image value in yaml file.

- deploy service
  ```
  kubectl create -f kube/svc.yaml
  ```

