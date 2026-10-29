# UVM extension agent

*Chapter: UVM extension library · source: attached*

Hi my name is Cristian Slav and in this tutorial we are going to talk about the UVM extension agent.
This is a diagram of our two agents from the APB and from the MD packages and, as you can see the API is identical.
The only difference is the type used to define these fields here.
But, with the right parameters, we can define an UVM extension agent class in which we can move all that API here.
And the parameters that we need are: the type of the virtual interface, the type of the item used by the monitor, and the type of the item used by the driver.
And in this way everything is moved to our UVM extension agent and the agents inside the APB and MD packages are quite clean, we only need here the constructor.
And in the constructor we declare with what types we want to override the types used for these fields here.
And with this, we finish implementing all the classes of our UVM extension package.
And now it's a good time to try to add some new features to our UVM extension package to see how difficult, or easy, is to do this.
And the feature that I want to add to our UVM extension package is related to the mechanism with which we configure an agent.
Currently, each of our agent is configured by creating the agent configuration instance inside the build phase of each of those agents.
And the agents are using the default values of those fields.
But a more commonly used mechanism to configure an UVM agent is to create the agent configuration instance at a higher level, for example in the build phase of the environment and the advantage for doing this is that when we create the instance of the agent configuration here, we have access to all the fields and methods from the environment so we can configure with whatever values we want.
But then to pass this agent configuration instance to our agent, we use the UVM configuration database.
So we will put this instance here, and then the agent will know to take from the UVM configuration database that instance and use it to configure all its components.
So this mechanism of creating the agent configuration instance at a higher level and pass it via the database, it's much more commonly used in our industry.
And as I told you, there are clear advantages in doing this.
But one thing that you'll also encounter in real projects is that it is quite common to use as the agent configuration class an uvm_object rather than an uvm_component like we have in our case.
In my opinion, we get more advantages in declaring the agent configuration class as a child of an uvm_component rather than an uvm_object because there are three main advantages.
First, the override is much more easier when we are using components.
Then also in components we have the UVM phases, so we can use for example the "end of elaboration" phase in the agent configuration class to do some more checks.
And the last advantage is related to visualization.
When we are running a simulation in GUI mode, most of the simulators will add some special features for the UVM components in the sense that you will see those in a tree like structure,so you can easily see the values of the fields inside.
But this is my personal opinion and as I told you, in practice it will be more common for you to see the agent configuration class as an uvm_object.
It is up to you whichever version you prefer.
So we will update our UVM extension package to also use this mechanism of configuring the agent via the UVM configuration database.
But in the same time, we will also keep the old mechanism of configuring the agents by creating the instance of the agent configuration inside the build phase of the agent.
So you will see what it takes to support both of these mechanisms inside our UVM extension package.
That's it for this tutorial.
We talked about the API of our UVM extension agent and we also talked about the update on the UVM extension package for the agent configuration mechanism.
In the next tutorial we will implement all these together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
