# An advanced technique for building UVM agents

*Chapter: UVM extension library · source: attached*

Hi, my name is Christiane Slav, and in this tutorial we are going to talk about an advanced technique for building UVM agents.
You saw that throughout our tutorials for building the app agent and the MDE agent, that there were a lot of similarities between these two.
First, the structure of the agent is the same.
We have the same components in our MDE agent as we have in the app agent, and not only the structure, but also inside.
The components have a very similar API.
And for example, if we look at the implementation of the app monitor, we can see that it is quite similar to the monitor we built for the MDE protocol.
This part highlighted with green.
It's common between the app monitor and the MDE monitor.
In both cases we are implementing some reset handler interface.
In both cases, we declare the agent config pointer, the output port, the pointer to the process for collect transaction tasks and so on.
And the only difference is basically this one the actual implementation of collect transaction task.
And we can find such similarities not only in the monitor but in the rest of the components of the agents.
So we have a lot of code which is similar between these agents.
And that common code is just boilerplate code in which we declare the same tasks, the same functions, the same fields in our classes that we have to copy from one agent to another.
And we can get rid of this common code from our agent.
By using inheritance, we can create a systemverilog package that we can call it UVM Extension Package.
And in this package, we can create base classes for all the components of the agents.
And in these base classes, we will put there the code which is common throughout our agents.
So we will have a base class for the agent configuration component.
A base class for the monitor, for the coverage driver sequencer, and also for the agent.
And then we can use the classes from this package to extend the corresponding classes in our agent.
The agent config, sequencer driver, and so on.
And in this way we can move in our UVM extension package, all the common code throughout our agents.
And of course we cannot move the entire common code from these agents, but some of these common code will remain.
And some of these common code we will not be able to remove because of the nature of Systemverilog and UVM library.
In each of those agent, you still have to declare the classes part of the agent, and in those classes you still have to.
For example, call that uvm component utils macro, and you still have to call the constructor in those classes.
And that is common code, but we cannot get rid of that.
But with such an UVM extension package, we can minimize the code shared by all these agents.
And throughout this section of our training, we will build this UVM extension package.
And once this is complete, then you can use this UVM extension package in your career.
Whenever you have to build a new UVM agent, you can quickly bring up a new UVM agent by extending its classes from these base classes.
And in this way, you get rid of a lot of common code that you otherwise had to copy from one agent to another.
And this copy paste is very prone to error.
You saw in the previous tutorials how often I did a mistake of forgetting to replace the name APB with the name MD, so this will be very helpful for you throughout your career.
In this section, what we will do is to create the UVM extension package with the purpose of minimizing the code in our CFS APB package and in our CFS MD package.
And I have a challenge for you.
Let's look now at how many lines of code our APB package has.
So it has 940 lines of code, and our MD package has 1279 of code.
And my challenge to you is the following.
Try to guess how many lines of code we will reduce with our UVM extension package, and write me a comment with your estimate.
Let's say maybe, um, I don't know.
Maybe you think it's something like 100 lines or 500 lines.
Take a guess and at the end of this section, we will see how many lines of code we will manage to reduce from these two packages.
And it will be very interesting to see how close you got with your estimate now at the beginning of this section.
That's it for this tutorial.
We talked about the UVM extension package, and in particular the base classes that will contain the common code.
And we will see how this will optimize our code in our project.
Thanks for watching and see you in the next tutorial.
Bye!
