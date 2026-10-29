# UVM extension coverage class

*Chapter: UVM extension library · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to code together the UVM extension coverage class.
First we are going to move to our UVM extension package these two classes for the index wrapper and we will get these two classes, which will be identical to the ones declared under the APB package, but only with this prefix changed.
And then we are going to code the UVM extension coverage class by moving some of the API from our APB package.
And once we finish with this, we will also adapt the MD package to use the UVM extension coverage class.
So let's start from our UVM extension coverage practice project, which we need to copy.
And let's resize the windows.
First let's create the UVM extension coverage file.
Let's include this file.
Now let's move from the APB package.
Those two classes for the cover index wrapper.
And we can also move this analysis implementation declaration here.
And we can simply rename this cfs apb to uvm XT.
Now let's align the code.
Now let's declare the UVM extension coverage class.
Now let's declare here in our UVM extension coverage class.
A pointer to the agent config, just like we did for the monitor.
And let's take from the APB some of the code.
From here we can take the port.
And let's fix the comment for the port.
It's a port for receiving the collected item.
We can take the initialization code.
And we can take the declaration of right item and handle reset.
And just to clarify things here we need right item here because we declared this port which is expecting to have this function here in this class.
And we also need this handle reset here because we specified that this class is implementing UVM extension reset handler.
Now let's go to the APB package and take some of the code from our coverage toString function.
And the code that we can take is this one, which is printing the coverage information from our UVM extension cover index wrapper.
And with this in the child classes of this one.
So in the APB and in the MD, we can use the return value from the parent of this coverage to string in order to print this information.
So let's do this now in the APB.
And it is simply a matter of adding here to the result, the return value of super dot coverage toString.
And we can remove this code from here.
Now here in the UVM extension coverage we discussed in the previous tutorial to also add that report phase from our MD package, which is printing the coverage information at the end in the report phase.
So let's do this now.
And again, I want to mention to you that printing the coverage information is not something that you want to do in a real project.
In a real project, you will have access to tools which will help you visualize the coverage.
And you don't need some printed messages like we did here.
But again, we did this in order to see some coverage values in EDA playground.
Now let's adapt our APB coverage to use as a parent this class from here.
Let's rename those CFS APB cover index wrapper to UVM cover index wrapper.
Let's connect that agent config pointer to this one and it will be the same code as we did in the monitor.
So let's copy paste this part here.
Now let's start the simulation to see if our project runs correctly with the APB coverage inheriting from our UVM extension coverage.
The simulation finished.
Let's look a little bit on the log.
And we can see only the printed information in the report phase from our APB agent is this one.
But if you remember, we also had here the printed information from our MD ethics and tax agents.
But that information is gone because we moved that report phase to our UVM extension coverage class.
And because we did not yet adapt the MD agent to inherit from this one, we no longer get this printed information at the end from the MD agents.
But now let's fix this.
Let's adapt our MD coverage to inherit from our UVM extension coverage class.
So let's start adapt our MD package.
First, we can remove this code with the cover index wrapper declaration.
Next, let's fix the parent class of cfs MD coverage.
We can get rid of this port item declaration from here and also in the constructor.
Now let's rename this one to UVM cover index wrapper.
Let's connect the pointer agent config from the parent class to this one.
And finally, let's fix the coverage to string declaration.
We can get rid of this code from here and we can add the result of the parent class.
And now let's try to run a simulation to see if our code runs correctly.
Also with our CFS MD coverage class inheriting from our UVM extension coverage.
The simulation finished.
Let's look on the log and see if our information from the MD agent was printed.
And here it is.
So this is the coverage information printed in the report phase from our TCS agent.
And we also have the child component information here.
And it is the same for our Erix agent.
And finally the APB.
So that's it for this tutorial.
We managed to implement our UVM extension coverage class.
And we adapt the APB and the MDP packages based on this.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye!
