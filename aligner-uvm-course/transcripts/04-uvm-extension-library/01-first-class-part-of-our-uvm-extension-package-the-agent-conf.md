# First class part of our UVM extension package, the Agent Configuration class

*Chapter: UVM extension library · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to talk about the first class part of our UVM extension package, the Agent Configuration class.
This is the UML diagram of the agent configuration classes from the APB and the MDE agents, and you can easily see here the common API.
From these two classes we declared as fields the virtual interface.
In both of these classes, active passive field has coverage and has checks.
They also have this stack threshold field.
But we cannot carry this stack threshold field to some common class, because we cannot really say that some future agent that we will develop will need such a field.
This stack threshold, usually this stack threshold field is required when we are developing an agent connected to some protocol in which we expect some feedback, some knowledge from the RTL, And if that knowledge does not come in some given threshold, then we issue an error.
So in such a scenario, we need this stack threshold.
But there are protocols which don't require some feedback from some duty to which we connect the agent.
So for this reason we cannot really carry this stack threshold to our common agent configuration class.
But these four fields we can carry up to our UVM extension agent configuration class.
One important thing to notice here is that for the virtual interface, we need a type of the virtual interface.
But this type we cannot really know in some pattern class here.
And this is why we will create a parameter in our UVM extension agent configuration class with the type of the virtual interface, because we really need the virtual interface as part of the agent configuration class, you cannot have an agent which drives some signals without a virtual interface.
Then we have all these getters and setters for the fields and the getters and setters for these four fields.
We can also carry up to the parent class.
In the constructor of these classes.
We have some initialization code for these fields.
So we can also carry this information there.
In the start of simulation phase we check if the virtual interface is set.
Otherwise we trigger an error.
So this code can be carried up to our parent class.
However, in the run phase we actually did this check in which we ensure that the has checks fields from the virtual interface is equal to the configuration from our agent configuration class.
This gethash checks, but this one is specific to each interface, so we cannot use inheritance when it comes to the interface in order to be able to declare some base interface which has this hash check field.
And because of this, we cannot really carry this code to our UVM extension agent configuration class.
And the last two tasks wait, reset start and wait reset end.
In these tasks, we simply implement the logic to wait for the reset to start or to end again.
This is specific to the interface that we are going to use.
So for the APB we are using this p reset n.
And remember that in the MD interface we have another signal called only reset n without this p.
But because these tasks are essential for our agent, remember that in the agent class we are using, uh, these tasks in order to know when to reset the entire agent.
So what we can do is to carry these two tasks in our UVM Extension Agent configuration class, but we will declare them as abstract.
But remember, it will be an abstract, just in the sense of UVM.
It would be difficult for us to declare these tasks as pure virtual.
We will declare them with a body in which we simply implement an UVM fatal message.
So you can see that there is a lot of API which we can implement in our common class, and this is how the diagram will look like with our UVM extension Agent configuration class.
This will have a parameter, the virtual interface type.
We will declare these four fields, but we will declare them not as a private or local how it was before.
We will declare them as protected in order to be able to access them in the child classes.
Then we will also have the getters and setters.
In the constructor we will initialize these fields.
In the start of simulation phase, we will check if the interface is set or not, and then we will have these abstract tasks with reset start and wait reset end.
And then our agent configuration classes will be quite simplified.
They will inherit from a UVM extension agent config class with this parameter as the virtual interface type.
And then in here we will only leave the code which is specific to each agent, the stock threshold here and here it will be stock threshold and sample delayed start transaction.
And then the getters and setters and the implementation of the wait reset start and wait reset end.
That's it.
For this tutorial we discussed about the API of our UVM Extension Agent Configuration class, and in the next tutorial we will implement all this together in the code.
Thanks for watching and see you in the next tutorial.
Bye!
