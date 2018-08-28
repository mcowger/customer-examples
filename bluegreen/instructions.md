#The Blue/Green Way:

First we create a deployment of our application....this is just a shorter version of the deployment spec you already have, except we are going to add one field to the metadata that includes the application version:

blue-deployment.yaml:
```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: pcc-deployment-blue
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app: pcc
        version: "1.10"  #APPLICATION VERSION
    spec:
      containers: 
        - name: pcc
          image: nginxdemos/hello:0.1  #include the specific version tag of the image
          ports:
            - name: http
              containerPort: 80
```
And we'll deploy that using kubectl:

```shell
kubectl apply -f blue-deployment.yaml
```
Next we need a service to reach that Deployment:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: pcc-service
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
    protocol: TCP
    name: http
  selector:
    app: pcc
    version:  "1.10"
```

Notice that the service uses the 'selectors' that match the 'labels' in the Deployment - this is how the Service decides which backend Pods should be supporting the service.  In this case, its looking for any Pod with 'app=pcc' and 'version=1.10'

At this point you can access the service over its NodePort using the port selected in the config (30080 in my example above)

Now that we have it up and running, we can experiment with deploying a new version:

deployment-green.yaml
```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: pcc-deployment-green
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app: pcc
        version: "1.11" #APPLICATION VERSION
    spec:
      containers: 
        - name: pcc
          image: nginxdemos/hello:0.2
          ports:
            - name: http
              containerPort: 80
```

In this one, we've updated the name of the deployment, along with the version number in the labels and the version number in the image (to correspond to our new build).

So when we deploy this, the service still wont use it or expose it to the outside world because the 'version' label doesn't match.   Lets deploy that with:

```shell
kubectl apply -f deployment-green.yaml
```

Now here comes the clever part - all we have to do to switch things over is adjust (`patch`) the Service definition with the new version number.  We can do that by editing and reapplying the file, or with a single patch command:

```shell
kubectl patch service pcc-service  -p '{"spec":{"selector":{"version":"1.11"}}}'
```

This updates the version label the service is looking for, which automatically changes the set of pods the Service is targeting.   Awesome - application is updated!

Now we can delete our old deployment:

```shell
kubectl delete deployment pcc-deployment-blue
```

Now, I notice in your existing script that you rename your apps so that the 'current' is always '-blue'....in K8S, object names are immutable, so we can't do that, which is why rather than naming your deployments 'blue' or 'green' that we'd recommend naming them by application version or Git commit hash or similar - that way its always easy to tell which version a deployment corresponds to just by its name.


---

#The Scale Over Way

This method doens't involve switching labels or anything like that, but it isn't a one-shot switches everything - there's a period during which both versions could get traffic, but its simpler to manage, and in the case of bad image builds, is more resilient.

We start with a similar deployment and service:

pcc-deployment-scaleover.yaml
```yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: pcc-deployment
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app: pcc
        version: "1.10" #APPLICATION VERSION
    spec:
      containers: 
        - name: pcc
          image: nginxdemos/hello:0.1
          ports:
            - name: http
              containerPort: 80
```
pcc-service.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: pcc-service
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
    protocol: TCP
    name: http
  selector:
    app: pcc
```

Note that the deployment name is more basic, and the Service is no longer looking for a specific version, just 'app: pcc'.

Now, we simply `patch` the deployment, and let kubernetes update the images in a Rolling Update fashion - it does all sorts of clever stuff like giving the containers time to start/warm up, checking their health status before making them live, making sure we have enough running to handle the load, etc:

```shell
kubectl patch deployment pcc-deployment  -p '{"spec": {"template": {"spec": {"containers": [{"name":"pcc","image": "nginxdemos/hello:0.2"}]}}}}'
```

As you can see, its notably simpler.
