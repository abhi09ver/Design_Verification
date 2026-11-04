# DUT functional coverage

*Chapter: Modeling and checking · source: attached*

Hi!
My name is Cristian Slav and in this tutorial we are going to talk about the DUT functional coverage.
This is the current image of our verification environment with all the components that we implemented so far and we will implement this DUT functional coverage in this component from our environment, the coverage component.
We already discussed about coverage when we built the coverage for the agents but just to iterate, coverage is a record of what happened and in other words what was verified.
When we thought about the APB and MD coverage, the starting point was the documentation for those protocols.
The same thing is valid for the DUT functional coverage.
The starting point is the specification, in our case is the Aligner specification.
So we start from the specification and we try to extract from each statement in the spec a functionality, a feature, that we want to cover.
Remember that we discussed for the ABB and MD protocols that we should organize the information that we want to cover in a tree-like structure which is called the verification plan.
The same thing is valid for the DUT functional coverage.
You should start from the specification and build this tree-like structure in which you put all the elements that you want your environment to cover.
The format of this verification plan file is different from company to company based on the methodology applied there.
So, for example, the format can be XML or MindMap or this custom format from Cadence tools called vplanx.
Regardless of the format, in the end you should obtain the same result.
You should get a tree-like structure in which you specify what you want to cover in your verification environment.
So, let's look over a usual organization of this verification plan.
First, you should have a branch for covering the register accesses and on this branch you can put the registers of your DUT.
In our case for the Aligner we have these four registers and for each register you should have all the fields inside that register.
And finally you can define some leaves in which you specify what you want to cover.
For example, for the SIZE field from the Control register we might want to cover the write value cross with the current value.
So you can imagine that we can define a lot of coverage elements for all the register fields.
Another important branch that you'll see in a verification plan is one called Features.
In this branch, you will have to identify all the features of the DUT.
For example, in the Aligner case, we might identify features like RX FIFO or TX FIFO or the Align feature and so on.
And for example, for the RX FIFO feature, we might want to cover the level of the FIFO when there is a push and a pop at the same time.
Remember that we had a synchronization issue for this scenario and also the RTL might have similar issues in such scenarios.
So for this reason you should have some coverage element to show you that you actually tested that scenario.
And another example would be for this Align feature.
Remember that we had to implement in our model a split function in order to take only several bytes out of an MD RX item in order to build the TX item.
So we want to make sure that we verified properly that functionality and for this we can define a coverage like this one.
We can have a cross between several fields, the values of SIZE and OFFSET fields from the Control register, the size and offset of the RX item, and the number of bytes that we need to take out of this RX item in order to build the TX item.
One last main branch that you'll see in such a verification plan will deal with the coverage on the interfaces.
So under this branch you'll find the coverage defined in all the agents.
And in our case we have three agents: one instance of the APB agent and two instances of the MD agent.
One very interesting feature that a verification plan usually has is that it is reusable.
This means that you can instantiate somehow here the verification plans that you define for the agents.
And notice how I put here the verification plan for the MD RX interface and for the MD TX interface.
Remember when we discussed the MD verification plan, we only discussed about one verification plan, so this means one file, regardless if the agent is instantiated on the RX or TX interface.
But in most of the implementations of a verification plan, you have the ability to reuse the same verification plan of an agent and bind it to different instances inside your environment.
Remember that I told you that each leaf in such a verification plan will have a property which will allow you to bind or map this leaf to an actual implementation from your environment.
So, for example, we can bind this leaf to this implementation from our verification environment.
The same thing will apply when the leaves are referenced verification plans.
In such a case, you will bind this instance of a verification plan with a particular agent instance inside your environment and for our two instances of the MD verification plan, we will specify different instances of the MD agent, the RX instance and the TX instance.
For example, when you are using the Cadence tools, so you are building this verification plan in a software called vManager, when you have to do this binding, the terminology there is that you have to specify the logical instance connected to this reference verification plan.
But as I told you, this will be different from company to company based on how they are building this verification plan.
Creating such a verification plan is not a trivial task.
This is not easy even for our simple Aligner RTL.
And in a real project, the specifications of the DUT that you have to verify might even have hundreds of pages.
So creating this verification plan is a very time-consuming task.
And normally you will have to do this verification plan in the beginning of the project before you write any line of code.
Such verification plan will have to be reviewed, usually by the design engineers and the concept engineers, so that everybody understands and agrees about what we will verify for that DUT.
Because creating such a verification plan is a big task, we will not have time in this tutorial to build a complete verification plan for our Aligner.
I just want to give you a sense of how such a verification plan should be organized.
And you can imagine that if building such a verification plan is a big task, then implementing it will require much more effort.
So, because of this reason, in the next tutorial we will only implement this leaf from our verification plan regarding the coverage for the split functionality.
So once you learn how to collect the coverage for this leaf, then you can apply the same technique for all the other elements part of your verification plan.
So let's see a short animation of this split functionality to be aware of why we need to cover this information, and then we will discuss the new API that we need to add in our environment in order to implement this leaf.
This is the block diagram of our Aligner RTL and let's consider that in the intermediate buffer we have 3 entries.
Now this Controller module will start to align this information and let's assume that the OFFSET is 0 and the SIZE is 4.
This means that the Controller will try to align this information.
And now, out of this last MD RX transaction, it will have to use only the first byte.
So, it will have to split this information and take only this byte here.
So, we want to cover this split functionality.
So, for this, we need to cover all the parameters of this split functionality.
So, this split functionality will depend on the OFFSET and SIZE from the Control register, will depend on the offset and size of this MD RX item, and it will also depend on the number of bytes needed in order to build a full MD TX item. in order to verify the split functionality, we will have to create a cross between all these five items.
So let's see what we need to add in our environment in order to implement this.
First we will have to create a class which will hold this information.
So we will have this split info class with all this information inside and our model will pass this information to the coverage via an analysis port.
Next, we will have to create the coverage component as this one does not exist in our environment, so the coverage component will extend from UVM component and it will also implement our reset handler.
Currently, we don't have anything to put in this handle_reset() function, so we will declare this function as an empty one.
In our coverage component, we will have to add an analysis implementation port through which our coverage will receive this information from the model.
So, because this is an analysis implementation port, we will also have to define a write() function and in that write() function we will sample the coverage information.
So, in this write() function we will call this sample() function of our cover group.
So, we will have this cover group called cover_split and in here we will define cover items with all this information and a cross between all these.
And just like we did for the coverage from the agents, we will define this coverage2string() function and we will call this in the report_phase().
So this will be our way of visualizing the coverage numbers in EDA Playground.
And just like before, I put here the comment: "Don't do this in a real project" because in a real project you don't need to print the coverage information, you'll have access to some graphical user interface though which you will be able to see the coverage.
We are only printing the coverage in our EDA Playground project just to be able to see the coverage percentage.
After that, we will define a field called has_coverage in our environment configuration class with which we will control if we have the coverage instance or not in our environment.
Next, in our model component we will have to define the port through which our model will send to the coverage this split_info and of course we will have to build this split_info object in the align() function after we did the split.
And finally, in our environment component, we will have to declare the coverage handler.
In the build_phase(), we will have to create the instance of the coverage based on the has_coverage field from the environment configuration class.
And in the connect_phase(), we will have to connect the port from the model with the port from the coverage.
So, that's the API that we will have to add in order to implement the coverage for our split functionality.
And as you can see, this is not an easy task even for one leaf from our verification plan.
So, you can imagine that for a complex verification plan, implementing the coverage from all the leaves is quite a time-consuming task.
So, in a real project you'll have to take this into consideration.
That's it for this tutorial.
We talked about the verification plan of a DUT and how you can organize it.
We talked about how we can send the coverage information from the model to the coverage component via the UVM analysis ports.
And finally, we talked about the API that we need to add in order to cover the split functionality.
In the next tutorial, we will add this coverage component in our environment and we will implement together this coverage for the split functionality.
Thanks for watching and see you in the next tutorial.
Bye!
